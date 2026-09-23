import 'dart:io';
import 'dart:convert';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
class Strings extends RecursiveAstVisitor<void> {
 final strings=<String>{};
 String? value(StringLiteral n) {
  if(n is SimpleStringLiteral) return n.value;
  if(n is AdjacentStrings) return n.strings.map(value).join();
  if(n is StringInterpolation) {var i=0;return n.elements.map((e)=>e is InterpolationString?e.value:'{${i++}}').join();}
  return null;
 }
 @override void visitSimpleStringLiteral(SimpleStringLiteral n) { add(n); }
 @override void visitStringInterpolation(StringInterpolation n) {add(n);super.visitStringInterpolation(n);}
 @override void visitAdjacentStrings(AdjacentStrings n) {add(n);}
 void add(StringLiteral n) {final s=value(n);if(s!=null&&RegExp('[А-Яа-яЁё]').hasMatch(s))strings.add(s);}
}
void main() {
 final v=Strings();
 for(final f in Directory('lib').listSync(recursive:true).whereType<File>().where((f)=>f.path.endsWith('.dart'))) {
  parseString(content:f.readAsStringSync(),throwIfDiagnostics:false).unit.accept(v);
 }
 File('build/strings.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(v.strings.toList()));
 print('Extracted ${v.strings.length} strings');
}
