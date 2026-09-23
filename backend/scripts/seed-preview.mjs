#!/usr/bin/env node
/**
 * Local preview fixtures only. Run from the repository root:
 * FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
 * FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node backend/scripts/seed-preview.mjs
 *
 * Never changes existing users or documents. Restarting with the same emulator
 * data preserves manual edits, moderation decisions, passwords and calendars.
 */
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const projectId = 'demo-event-match';
const requiredHosts = {
  FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099',
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080',
};
for (const [variable, expected] of Object.entries(requiredHosts)) {
  if (process.env[variable] !== expected) {
    throw new Error(`${variable} must be exactly ${expected}; cloud access is forbidden.`);
  }
}
if (process.argv.length !== 2) {
  throw new Error('This script takes no arguments; the local project is fixed to demo-event-match.');
}

const password = 'EventMatch2026!';
const eventId = 'preview-wedding-2026-11-14';
const hostSelectionId = 'preview-hosts';
const photoSelectionId = 'preview-photographers';
const preferences = 'Тестовое мероприятие: спокойная атмосфера, 50 гостей.';
const fixtures = [
  { key: 'client', email: 'client@example.com', name: 'Тест Заказчик' },
  { key: 'admin', email: 'admin@example.com', name: 'Тест Администратор' },
  {
    key: 'contractor', email: 'contractor@example.com', name: 'Тест Ведущий на проверке',
    category: 'Ведущий', price: 380000, pending: true,
    description: 'Тестовый профиль для проверки модерации. Ведение свадеб и корпоративов, программа согласуется с заказчиком.',
  },
  {
    key: 'host-1', email: 'host1@example.com', name: 'Тест Ведущий — камерная свадьба',
    category: 'Ведущий', price: 350000,
    description: 'Тестовый профиль. Спокойная программа, знакомство гостей, координация тостов и согласованный сценарий.',
  },
  {
    key: 'host-2', email: 'host2@example.com', name: 'Тест Ведущий — два языка',
    category: 'Ведущий', price: 450000,
    description: 'Тестовый профиль. Ведение на русском и казахском, семейные традиции и индивидуальный тайминг.',
  },
  {
    key: 'host-3', email: 'host3@example.com', name: 'Тест Ведущий — интерактив',
    category: 'Ведущий', price: 550000,
    description: 'Тестовый профиль. Интерактивная программа, музыкальные паузы и помощь с организацией вечера.',
  },
  {
    key: 'photo-1', email: 'photo1@example.com', name: 'Тест Фотограф — живые кадры',
    category: 'Фотограф', price: 250000,
    description: 'Тестовый профиль. Репортажная свадебная съёмка и помощь с естественным позированием.',
  },
  {
    key: 'photo-2', email: 'photo2@example.com', name: 'Тест Фотограф — полный день',
    category: 'Фотограф', price: 320000,
    description: 'Тестовый профиль. Подготовка, церемония, прогулка и банкет, отбор и обработка фотографий.',
  },
  {
    key: 'venue', email: 'venue@example.com', name: 'Тест Банкетный зал',
    category: 'Банкетный зал', price: 900000,
    description: 'Тестовый профиль. Светлый зал для камерной свадьбы; меню, вместимость и итоговую стоимость нужно уточнить.',
  },
  {
    key: 'decorator', email: 'decorator@example.com', name: 'Тест Декоратор',
    category: 'Декоратор', price: 200000,
    description: 'Тестовый профиль. Оформление церемонии и столов, спокойная палитра и согласование эскиза.',
  },
];

const stamp = () => FieldValue.serverTimestamp();
const app = initializeApp({ projectId }, 'local-preview-seed');
const auth = getAuth(app);
const store = getFirestore(app);
const summary = { projectId, createdUsers: [], preservedUsers: [], createdDocuments: [], preservedDocuments: [], warnings: [] };

function profileContent(fixture) {
  return {
    name: fixture.name, city: 'Алматы', categories: [fixture.category],
    price: fixture.price, formats: ['свадьба', 'корпоратив', 'день рождения'],
    languages: ['русский', 'казахский'], maxHours: 12,
    description: fixture.description,
    contact: fixture.email,
    portfolioUrls: [`https://example.com/preview/${fixture.key}`],
  };
}

function contractorSnapshot(fixture, historicalPrice = fixture.price) {
  const content = profileContent(fixture);
  return {
    id: fixture.uid, anon_name: content.name, city: content.city,
    categories: content.categories, price_from_kzt: historicalPrice,
    event_formats: content.formats, languages: content.languages,
    max_hours: content.maxHours, busy_dates: [], description: content.description,
    synthetic: false, city_imputed: false, price_imputed: false,
    is_live: true, contact: content.contact, portfolio_urls: content.portfolioUrls,
  };
}

function audit(actorId, resourceType, resourceId, revision, action) {
  return {
    actorId, resourceType, resourceId, revision, action,
    reason: action === 'approved' ? '' : 'Создано для локального тестирования; тестовые данные.',
    createdAt: stamp(),
  };
}

// Firestore create preconditions and transaction reads also protect concurrent
// seed runs. This helper never uses set/update/delete on an existing document.
async function createMissing(entries, { linked = false } = {}) {
  const result = await store.runTransaction(async (transaction) => {
    const refs = entries.map(([path]) => store.doc(path));
    const existing = await transaction.getAll(...refs);
    const created = [], preserved = [];
    const skipLinked = linked && existing.some((document) => document.exists);
    for (let index = 0; index < entries.length; index += 1) {
      const [path, data] = entries[index];
      if (existing[index].exists || skipLinked) {
        preserved.push(path);
      } else {
        transaction.create(refs[index], data);
        created.push(path);
      }
    }
    return { created, preserved, partial: skipLinked && existing.some((document) => !document.exists) };
  });
  summary.createdDocuments.push(...result.created);
  summary.preservedDocuments.push(...result.preserved);
  if (result.partial) {
    summary.warnings.push(`Preserved an existing linked fixture instead of changing its moderation/role state: ${entries[0][0]}`);
  }
}

async function ensureUser(fixture) {
  try {
    const existing = await auth.getUserByEmail(fixture.email);
    summary.preservedUsers.push(fixture.email);
    if (!existing.emailVerified || existing.disabled) {
      summary.warnings.push(`Existing user ${fixture.email} is unverified or disabled; it was not changed.`);
    }
    return existing;
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }
  const uid = `preview-${fixture.key}`;
  if ((await store.doc(`deletedAccounts/${uid}`).get()).exists) {
    throw new Error(`Refusing to recreate deleted preview account ${uid}.`);
  }
  try {
    const created = await auth.createUser({ uid, email: fixture.email, password, displayName: fixture.name, emailVerified: true });
    summary.createdUsers.push(fixture.email);
    return created;
  } catch (error) {
    if (error.code !== 'auth/email-already-exists') throw error;
    summary.preservedUsers.push(fixture.email);
    return auth.getUserByEmail(fixture.email);
  }
}

try {
  // Resolve email to the existing UID, retaining any previously created login.
  for (const fixture of fixtures) {
    const user = await ensureUser(fixture);
    fixture.uid = user.uid;
    if ((await store.doc(`deletedAccounts/${fixture.uid}`).get()).exists) {
      throw new Error(`Refusing to seed a deleted account: ${fixture.email}.`);
    }
    await createMissing([[`accounts/${fixture.uid}`, {
      uid: fixture.uid, name: fixture.name, email: fixture.email,
      status: 'active', deletionRequested: false, revision: 1,
      createdAt: stamp(), updatedAt: stamp(),
    }]]);
  }

  const byKey = new Map(fixtures.map((fixture) => [fixture.key, fixture]));
  const administrator = byKey.get('admin');
  await createMissing([
    [`staffAccess/${administrator.uid}`, { role: 'admin', revision: 1, updatedAt: stamp() }],
    [`audit/staff_${administrator.uid}_1`, audit('trusted-preview-seed', 'staff', administrator.uid, 1, 'admin')],
  ], { linked: true });

  for (const fixture of fixtures.filter((entry) => entry.category)) {
    const content = profileContent(fixture);
    const revision = fixture.pending ? 2 : 3;
    const entries = [[`profiles/${fixture.uid}`, {
      ownerId: fixture.uid, revision, status: fixture.pending ? 'pending' : 'approved',
      content, reason: '', updatedAt: stamp(),
    }]];
    if (!fixture.pending) {
      entries.push(
        [`publishedProfiles/${fixture.uid}`, {
          ownerId: fixture.uid, revision: 1, profileRevision: revision,
          published: true, content, updatedAt: stamp(),
        }],
        [`audit/profile_${fixture.uid}_${revision}`, audit(administrator.uid, 'profile', fixture.uid, revision, 'approved')],
      );
    }
    // Do not publish an existing pending profile, or restore a removed card.
    await createMissing(entries, { linked: true });
    await createMissing([9, 10, 11, 12].map((month) => [
      `calendars/${fixture.uid}/months/2026-${String(month).padStart(2, '0')}`,
      {
        ownerId: fixture.uid, year: 2026, month,
        busyDays: month === 10 ? [10, 24] : month === 11 ? [7, 21] : [5, 19],
        confirmedAt: stamp(),
      },
    ]));
  }

  const client = byKey.get('client');
  const accountPath = `accounts/${client.uid}`;
  const hosts = ['host-1', 'host-2', 'host-3'].map((key) => byKey.get(key));
  const photographers = ['photo-1', 'photo-2'].map((key) => byKey.get(key));
  function selection(name, category, budget, candidates) {
    return {
      eventId, name,
      request: {
        city: 'Алматы', date: '2026-11-14', event_format: 'свадьба',
        category, budget_kzt: budget, hours: 6, language: 'русский', preferences,
      },
      entries: candidates.map((fixture) => ({
        // One historical price intentionally differs to exercise comparison.
        contractor: contractorSnapshot(fixture, fixture.key === 'host-1' ? 325000 : fixture.price),
        explanation: 'Тестовая сохранённая подборка: Алматы, свадьба, русский язык, 6 часов и бюджет категории. Актуальность проверяется при открытии плана.',
      })),
      savedAt: stamp(),
    };
  }
  await createMissing([
    [`${accountPath}/events/${eventId}`, {
      name: 'Тест Свадьба в Алматы', city: 'Алматы', date: '2026-11-14',
      format: 'свадьба', preferences, updatedAt: stamp(),
    }],
    [`${accountPath}/selections/${hostSelectionId}`, selection('Тест Ведущие — три варианта', 'Ведущий', 1000000, hosts)],
    [`${accountPath}/selections/${photoSelectionId}`, selection('Тест Фотографы — два варианта', 'Фотограф', 400000, photographers)],
    [`${accountPath}/eventPlans/${eventId}`, {
      schemaVersion: 1, revision: 1, totalBudgetKzt: 1500000,
      choices: {
        'Ведущий': { selectionId: hostSelectionId, contractorId: hosts[0].uid },
        'Фотограф': { selectionId: photoSelectionId, contractorId: photographers[0].uid },
      },
      completedTaskIds: ['confirm_scope'],
      notes: 'Тестовая заметка: сравнить ведущих, уточнить полную стоимость и условия. Отметки checklist демонстрационные.',
      updatedAt: stamp(),
    }],
    [`${accountPath}/favorites/${hosts[0].uid}`, { contractor: contractorSnapshot(hosts[0]), savedAt: stamp() }],
  ]);

  console.log(JSON.stringify({
    ...summary,
    eventId,
    plannerRoute: `/client/planner?event=${eventId}`,
    primaryLogins: ['client@example.com', 'contractor@example.com', 'admin@example.com'],
    passwordForNewUsers: password,
    note: 'Existing users retain their passwords. Existing calendars are not refreshed; reconfirm them in the contractor workspace when needed.',
  }, null, 2));
} catch (error) {
  console.error(`Local preview seed failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  await deleteApp(app);
}
