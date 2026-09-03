const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const controllerPath = path.resolve(
  __dirname,
  "../roles/macos/files/chrome-tab-gc-extension/tab_gc.js",
);

const ChromeTabGC = require(controllerPath);

const hour = 60 * 60 * 1000;

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function missingTabError(tabId) {
  return new Error(`No tab with id: ${tabId}`);
}

function resolveBehavior(behavior, context) {
  if (typeof behavior === "function") {
    return behavior(context);
  }
  return behavior;
}

function createHarness({
  tabs,
  initialState = {},
  storageGetError = null,
  queryError = null,
  getBehaviors = new Map(),
  removeBehaviors = new Map(),
}) {
  const listeners = {
    activated: [],
    updated: [],
    alarm: [],
  };
  let tabOrder = tabs.map((tab) => tab.id);
  const tabsById = new Map(tabs.map((tab) => [tab.id, clone(tab)]));
  const alarmCreations = [];
  const queryCalls = [];
  const getCalls = [];
  const removeCalls = [];
  const operations = [];
  const storageSetCalls = [];
  let sessionState = clone(initialState);
  let currentStorageGetError = storageGetError;
  let currentQueryError = queryError;

  const chrome = {
    alarms: {
      create(name, info) {
        alarmCreations.push({ name, info: clone(info) });
      },
      onAlarm: {
        addListener(listener) {
          listeners.alarm.push(listener);
        },
      },
    },
    storage: {
      session: {
        async get(defaults = {}) {
          if (currentStorageGetError) throw currentStorageGetError;
          return { ...clone(defaults), ...clone(sessionState) };
        },
        async set(patch) {
          storageSetCalls.push(clone(patch));
          sessionState = { ...sessionState, ...clone(patch) };
        },
      },
    },
    tabs: {
      onActivated: {
        addListener(listener) {
          listeners.activated.push(listener);
        },
      },
      onUpdated: {
        addListener(listener) {
          listeners.updated.push(listener);
        },
      },
      async query(queryInfo) {
        queryCalls.push(clone(queryInfo));
        operations.push("query");
        if (currentQueryError) throw currentQueryError;
        return tabOrder
          .map((id) => tabsById.get(id))
          .filter(Boolean)
          .map((tab) => clone(tab));
      },
      async get(tabId) {
        getCalls.push(tabId);
        operations.push(`get:${tabId}`);
        if (getBehaviors.has(tabId)) {
          const result = resolveBehavior(getBehaviors.get(tabId), {
            deleteTab,
            getTab: (id) => clone(tabsById.get(id)),
            tabId,
          });
          if (result instanceof Error) throw result;
          return clone(result);
        }
        const tab = tabsById.get(tabId);
        if (!tab) throw missingTabError(tabId);
        return clone(tab);
      },
      async remove(tabId) {
        removeCalls.push(tabId);
        operations.push(`remove:${tabId}`);
        if (removeBehaviors.has(tabId)) {
          const result = resolveBehavior(removeBehaviors.get(tabId), {
            deleteTab,
            getTab: (id) => clone(tabsById.get(id)),
            tabId,
          });
          if (result instanceof Error) throw result;
        }
        deleteTab(tabId);
      },
    },
  };

  async function emitActivated(tabId, windowId = 1) {
    for (const listener of listeners.activated) {
      await listener({ tabId, windowId });
    }
  }

  async function emitUpdated(tabId, changeInfo, tab = null) {
    const currentTab = tabsById.get(tabId) || { id: tabId };
    const nextTab = tab ? clone(tab) : { ...currentTab, ...clone(changeInfo) };
    tabsById.set(tabId, nextTab);
    if (!tabOrder.includes(tabId)) tabOrder.push(tabId);
    for (const listener of listeners.updated) {
      await listener(tabId, clone(changeInfo), clone(nextTab));
    }
  }

  function deleteTab(tabId) {
    tabsById.delete(tabId);
    tabOrder = tabOrder.filter((id) => id !== tabId);
  }

  return {
    chrome,
    alarmCreations,
    listeners,
    queryCalls,
    getCalls,
    removeCalls,
    operations,
    storageSetCalls,
    emitActivated,
    emitUpdated,
    deleteTab,
    hasTab(tabId) {
      return tabsById.has(tabId);
    },
    sessionState() {
      return clone(sessionState);
    },
    setQueryError(error) {
      currentQueryError = error;
    },
    setStorageGetError(error) {
      currentStorageGetError = error;
    },
    setTabOrder(ids) {
      tabOrder = [...ids];
    },
    updateTab(tabId, patch) {
      const currentTab = tabsById.get(tabId) || { id: tabId };
      tabsById.set(tabId, { ...currentTab, ...clone(patch) });
      if (!tabOrder.includes(tabId)) tabOrder.push(tabId);
    },
  };
}

function createController(harness, clock, options = {}) {
  return ChromeTabGC.create({
    chrome: harness.chrome,
    now: () => clock.now,
    idleMs: hour,
    alarmPeriodMinutes: 1,
    ...options,
  });
}

function defaultTabs(now) {
  return [
    { id: 1, active: false, pinned: false, lastAccessed: now - hour },
    { id: 2, active: true, pinned: false, lastAccessed: now - hour * 2 },
    { id: 3, active: false, pinned: true, lastAccessed: now - hour * 2 },
  ];
}

test("start registers listeners and startup grace closes nothing", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({ tabs: defaultTabs(clock.now) });
  const controller = createController(harness, clock);

  await controller.start();
  await controller.collect();

  assert.deepEqual(harness.alarmCreations, [
    { name: "chrome-tab-gc", info: { periodInMinutes: 1 } },
  ]);
  assert.equal(harness.listeners.activated.length, 1);
  assert.equal(harness.listeners.updated.length, 1);
  assert.equal(harness.listeners.alarm.length, 1);
  assert.deepEqual(harness.queryCalls, [{}]);
  assert.deepEqual(harness.getCalls, []);
  assert.deepEqual(harness.removeCalls, []);
});

test("later pass closes the exact-threshold inactive unpinned tab and preserves active and pinned tabs", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({ tabs: defaultTabs(clock.now) });
  const controller = createController(harness, clock);

  await controller.start();
  clock.now += hour;
  await controller.collect();

  assert.deepEqual(harness.getCalls, [1]);
  assert.deepEqual(harness.removeCalls, [1]);
  assert.ok(harness.hasTab(2));
  assert.ok(harness.hasTab(3));
  assert.ok(
    harness.operations.indexOf("get:1") < harness.operations.indexOf("remove:1"),
  );
});

test("final revalidation sees active or pinned and skips removal", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({
    tabs: [
      { id: 1, active: false, pinned: false, lastAccessed: clock.now - hour },
      { id: 2, active: false, pinned: false, lastAccessed: clock.now - hour },
    ],
    getBehaviors: new Map([
      [1, { id: 1, active: true, pinned: false, lastAccessed: clock.now - hour }],
      [2, { id: 2, active: false, pinned: true, lastAccessed: clock.now - hour }],
    ]),
  });
  const controller = createController(harness, clock);

  await controller.start();
  clock.now += hour;
  await controller.collect();

  assert.deepEqual(harness.getCalls, [1, 2]);
  assert.deepEqual(harness.removeCalls, []);
});

test("activation refreshes one tab", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({
    tabs: [
      { id: 1, active: false, pinned: false, lastAccessed: clock.now - hour },
      { id: 2, active: false, pinned: false, lastAccessed: clock.now - hour },
    ],
  });
  const controller = createController(harness, clock);

  await controller.start();
  clock.now += hour;
  await harness.emitActivated(1);
  await controller.collect();

  assert.equal(harness.sessionState().browserGraceAt, 2_000_000_000_000);
  assert.equal(harness.sessionState().activityByTab[1], clock.now);
  assert.deepEqual(harness.removeCalls, [2]);
  assert.ok(harness.hasTab(1));
});

test("pinned-to-unpinned transition grants fresh grace", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({
    tabs: [{ id: 1, active: false, pinned: true, lastAccessed: clock.now - hour * 2 }],
  });
  const controller = createController(harness, clock);

  await controller.start();
  clock.now += hour;
  await harness.emitUpdated(1, { pinned: false }, {
    id: 1,
    active: false,
    pinned: false,
    lastAccessed: 2_000_000_000_000 - hour * 2,
  });
  await controller.collect();

  assert.equal(harness.sessionState().unpinnedAtByTab[1], clock.now);
  assert.deepEqual(harness.removeCalls, []);

  for (let minute = 0; minute < 59; minute += 1) {
    clock.now += 60 * 1000;
    await controller.collect();
  }

  assert.deepEqual(harness.removeCalls, []);

  clock.now += 60 * 1000;
  await controller.collect();

  assert.deepEqual(harness.removeCalls, [1]);
});

test("pinning does not make a tab eligible", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({
    tabs: [{ id: 1, active: false, pinned: false, lastAccessed: clock.now - hour * 2 }],
  });
  const controller = createController(harness, clock);

  await controller.start();
  clock.now += hour;
  await harness.emitUpdated(1, { pinned: true });
  await controller.collect();

  assert.deepEqual(harness.sessionState().unpinnedAtByTab, {});
  assert.deepEqual(harness.removeCalls, []);
  assert.ok(harness.hasTab(1));
});

test("reordered and moved tabs retain identity by ID", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({
    tabs: [
      { id: 1, active: false, pinned: false, lastAccessed: clock.now - hour },
      { id: 2, active: false, pinned: false, lastAccessed: clock.now - hour },
    ],
  });
  const controller = createController(harness, clock);

  await controller.start();
  clock.now += hour / 2;
  await harness.emitActivated(1);
  harness.setTabOrder([2, 1]);
  clock.now += hour / 2;
  await controller.collect();

  assert.deepEqual(harness.removeCalls, [2]);
  assert.ok(harness.hasTab(1));
});

test("missing tabs are pruned after a complete enumeration", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({
    tabs: [{ id: 1, active: false, pinned: false, lastAccessed: clock.now }],
    initialState: {
      browserGraceAt: clock.now,
      lastSweepAt: 0,
      activityByTab: { 1: clock.now, 99: clock.now - 1 },
      unpinnedAtByTab: { 99: clock.now - 2 },
    },
  });
  const controller = createController(harness, clock);

  await controller.start();
  await controller.collect();

  assert.deepEqual(harness.sessionState().activityByTab, { 1: clock.now });
  assert.deepEqual(harness.sessionState().unpinnedAtByTab, {});
});

test("multiple active tabs in separate windows remain", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({
    tabs: [
      { id: 1, active: true, pinned: false, lastAccessed: clock.now - hour * 2, windowId: 1 },
      { id: 2, active: true, pinned: false, lastAccessed: clock.now - hour * 2, windowId: 2 },
      { id: 3, active: false, pinned: false, lastAccessed: clock.now - hour },
    ],
  });
  const controller = createController(harness, clock);

  await controller.start();
  clock.now += hour;
  await controller.collect();

  assert.deepEqual(harness.removeCalls, [3]);
  assert.ok(harness.hasTab(1));
  assert.ok(harness.hasTab(2));
});

test("late alarm grants global grace", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({
    tabs: [{ id: 1, active: false, pinned: false, lastAccessed: clock.now - hour * 2 }],
  });
  const controller = createController(harness, clock);

  await controller.start();
  await controller.collect();
  clock.now += hour + 3 * 60 * 1000;
  await controller.collect();

  assert.equal(harness.sessionState().browserGraceAt, clock.now);
  assert.deepEqual(harness.removeCalls, []);
});

test("clock rollback cannot close early", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({
    tabs: [{ id: 1, active: false, pinned: false, lastAccessed: clock.now - hour * 2 }],
  });
  const controller = createController(harness, clock);

  await controller.start();
  await controller.collect();
  clock.now -= 5 * 60 * 1000;
  await controller.collect();

  assert.deepEqual(harness.removeCalls, []);
  assert.ok(harness.hasTab(1));
});

test("storage failure closes nothing", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({
    tabs: [{ id: 1, active: false, pinned: false, lastAccessed: clock.now - hour * 2 }],
  });
  const controller = createController(harness, clock);

  await controller.start();
  clock.now += hour;
  harness.setStorageGetError(new Error("storage failed"));

  await assert.doesNotReject(() => controller.collect());
  assert.deepEqual(harness.queryCalls, []);
  assert.deepEqual(harness.removeCalls, []);
});

test("enumeration failure closes nothing", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({
    tabs: [{ id: 1, active: false, pinned: false, lastAccessed: clock.now - hour * 2 }],
  });
  const controller = createController(harness, clock);

  await controller.start();
  clock.now += hour;
  harness.setQueryError(new Error("query failed"));

  await assert.doesNotReject(() => controller.collect());
  assert.deepEqual(harness.removeCalls, []);
  assert.ok(harness.hasTab(1));
});

test("candidate disappearance and removal failure do not affect other candidates", async () => {
  const clock = { now: 2_000_000_000_000 };
  const harness = createHarness({
    tabs: [
      { id: 1, active: false, pinned: false, lastAccessed: clock.now - hour * 2 },
      { id: 2, active: false, pinned: false, lastAccessed: clock.now - hour * 2 },
      { id: 3, active: false, pinned: false, lastAccessed: clock.now - hour * 2 },
    ],
    initialState: {
      browserGraceAt: clock.now - hour * 3,
      lastSweepAt: 0,
      activityByTab: { 1: clock.now - hour * 3, 2: clock.now - hour * 3, 3: clock.now - hour * 3 },
      unpinnedAtByTab: { 1: clock.now - hour * 3, 2: clock.now - hour * 3, 3: clock.now - hour * 3 },
    },
    getBehaviors: new Map([
      [1, ({ deleteTab, tabId }) => {
        deleteTab(tabId);
        return missingTabError(tabId);
      }],
    ]),
    removeBehaviors: new Map([[2, new Error("remove failed")]]),
  });
  const controller = createController(harness, clock);

  await controller.start();
  clock.now += hour;

  await assert.doesNotReject(() => controller.collect());
  assert.deepEqual(harness.getCalls, [1, 2, 3]);
  assert.deepEqual(harness.removeCalls, [2, 3]);
  assert.ok(harness.hasTab(2));
  assert.ok(!harness.hasTab(3));
  assert.deepEqual(harness.sessionState().activityByTab, {
    2: 2_000_000_000_000 - hour * 3,
  });
  assert.deepEqual(harness.sessionState().unpinnedAtByTab, {
    2: 2_000_000_000_000 - hour * 3,
  });
});
