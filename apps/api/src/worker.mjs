import { spawn, execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { resolve, dirname } from 'node:path';
import { root } from './database.mjs';

export class MatchingWorker {
  constructor() {
    let binary = process.env.DART_BIN || 'dart';
    if (!process.env.DART_BIN && process.platform === 'win32') {
      const located = execFileSync('where.exe',['dart'],{encoding:'utf8',windowsHide:true}).trim().split(/\r?\n/);
      binary = located.find(p => p.endsWith('.exe')) || resolve(dirname(located[0]),'cache/dart-sdk/bin/dart.exe');
      if (!existsSync(binary)) throw Error('Set DART_BIN to the full dart.exe path');
    }
    this.ready = new Promise((resolve,reject) => { this.resolveReady=resolve; this.rejectReady=reject; });
    this.startTimer = setTimeout(()=>this.rejectReady(Error('Matching worker startup timeout')),15000);
    // shell:false prevents payloads or paths becoming shell commands.
    this.child = spawn(binary, ['run', 'tool/matching_worker.dart'], {
      cwd: resolve(root, 'apps/event_match'), stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true,
    });
    this.pending = new Map(); this.sequence = 0; this.failed = false;
    createInterface({input: this.child.stdout}).on('line', line => {
      try {
        const response = JSON.parse(line);
        if (response.ready) { clearTimeout(this.startTimer);this.resolveReady();return; }
        const pending = this.pending.get(response.id);
        if (!pending) return;
        clearTimeout(pending.timer); this.pending.delete(response.id);
        response.error ? pending.reject(Error('Invalid matching request')) : pending.resolve(response.result);
      } catch { /* Ignore non-protocol compiler messages. */ }
    });
    this.child.stderr.on('data', () => {});
    const fail = () => {
      clearTimeout(this.startTimer);this.rejectReady(Error('Matching worker unavailable'));
      this.failed = true;
      for (const p of this.pending.values()) { clearTimeout(p.timer); p.reject(Error('Matching worker unavailable')); }
      this.pending.clear();
    };
    this.child.on('error', fail); this.child.on('exit', fail);
    this.child.stdin.on('error', fail);
  }
  match(catalog, request) {
    if (this.failed) return Promise.reject(Error('Matching worker unavailable'));
    const id = ++this.sequence;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.pending.delete(id); reject(Error('Matching worker timeout')); }, 1800);
      this.pending.set(id, {resolve, reject, timer});
      this.child.stdin.write(JSON.stringify({id, catalog, request})+'\n');
    });
  }
  close() { this.child.kill(); }
}
