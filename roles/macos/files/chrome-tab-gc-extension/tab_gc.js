const DEFAULT_IDLE_MS = 60 * 60 * 1000;
const DEFAULT_ALARM_PERIOD_MINUTES = 1;
const WAKE_GAP_MULTIPLIER = 2;
const ALARM_NAME = "chrome-tab-gc";
const DEFAULT_STATE = Object.freeze({
  browserGraceAt: 0,
  lastSweepAt: 0,
  activityByTab: Object.freeze({}),
  unpinnedAtByTab: Object.freeze({}),
});

function normalizeState(state) {
  return {
    browserGraceAt: Number(state.browserGraceAt) || 0,
    lastSweepAt: Number(state.lastSweepAt) || 0,
    activityByTab: { ...(state.activityByTab || {}) },
    unpinnedAtByTab: { ...(state.unpinnedAtByTab || {}) },
  };
}

function tabTimestamp(map, tabId) {
  return Number(map[tabId]) || 0;
}

function effectiveActivityAt(tab, state) {
  return Math.max(
    Number(tab.lastAccessed) || 0,
    state.browserGraceAt,
    tabTimestamp(state.activityByTab, tab.id),
    tabTimestamp(state.unpinnedAtByTab, tab.id),
  );
}

function isEligible(tab, state, idleMs, currentNow) {
  if (!tab || tab.active || tab.pinned) return false;
  return currentNow - effectiveActivityAt(tab, state) >= idleMs;
}

function isMissingTabError(error) {
  return /no tab with id/i.test(String(error && error.message));
}

function pruneMap(map, liveIds, removedIds) {
  const nextMap = {};

  for (const [tabId, timestamp] of Object.entries(map || {})) {
    if (!liveIds.has(Number(tabId))) continue;
    if (removedIds.has(Number(tabId))) continue;
    nextMap[tabId] = timestamp;
  }

  return nextMap;
}

function create({
  chrome,
  now = Date.now,
  idleMs = DEFAULT_IDLE_MS,
  alarmPeriodMinutes = DEFAULT_ALARM_PERIOD_MINUTES,
}) {
  let started = false;
  let stateMutationQueue = Promise.resolve();

  async function readState() {
    return normalizeState(await chrome.storage.session.get(DEFAULT_STATE));
  }

  function enqueueStateMutation(work) {
    const queuedWork = stateMutationQueue.then(work, work);
    stateMutationQueue = queuedWork.then(
      () => undefined,
      () => undefined,
    );
    return queuedWork;
  }

  async function waitForStateMutations() {
    await stateMutationQueue;
  }

  async function mutateState(mutator, context) {
    try {
      return await enqueueStateMutation(async () => {
        const state = await readState();
        const nextState = normalizeState((await mutator(state)) || state);
        await chrome.storage.session.set(nextState);
        return nextState;
      });
    } catch (error) {
      console.error(`ChromeTabGC: ${context}`, error);
      return null;
    }
  }

  async function readSettledState(context) {
    try {
      await waitForStateMutations();
      return await readState();
    } catch (error) {
      console.error(`ChromeTabGC: ${context}`, error);
      return null;
    }
  }

  async function initializeState() {
    return mutateState((state) => {
      const startedAt = now();
      if (!state.browserGraceAt) {
        state.browserGraceAt = startedAt;
      }
      if (!state.lastSweepAt) {
        state.lastSweepAt = startedAt;
      }
      return state;
    }, "failed to initialize state");
  }

  async function recordActivity(tabId) {
    return mutateState((state) => {
      state.activityByTab[tabId] = now();
      return state;
    }, `failed to record activity for tab ${tabId}`);
  }

  async function recordUnpinned(tabId) {
    return mutateState((state) => {
      state.unpinnedAtByTab[tabId] = now();
      return state;
    }, `failed to record unpinned grace for tab ${tabId}`);
  }

  async function start() {
    if (started) return;
    started = true;

    chrome.tabs.onActivated.addListener(({ tabId }) => recordActivity(tabId));
    chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
      if (changeInfo && changeInfo.pinned === false) {
        return recordUnpinned(tabId);
      }
      return undefined;
    });
    chrome.alarms.onAlarm.addListener((alarm) => {
      if (!alarm || alarm.name === ALARM_NAME) {
        return collect();
      }
      return undefined;
    });

    const existingAlarm = await chrome.alarms.get(ALARM_NAME);
    if (!existingAlarm) {
      chrome.alarms.create(ALARM_NAME, { periodInMinutes: alarmPeriodMinutes });
    }
    await initializeState();
  }

  async function collect() {
    const currentNow = now();
    const wakeGapMs = alarmPeriodMinutes * 60 * 1000 * WAKE_GAP_MULTIPLIER;
    const state = await readSettledState("failed to read state");
    if (!state) return;

    if (!state.browserGraceAt || !state.lastSweepAt) {
      await mutateState((latestState) => {
        latestState.browserGraceAt = currentNow;
        latestState.lastSweepAt = currentNow;
        return latestState;
      }, "failed to initialize recovered state");
      return;
    }

    if (
      state.lastSweepAt &&
      (currentNow < state.lastSweepAt || currentNow - state.lastSweepAt > wakeGapMs)
    ) {
      state.browserGraceAt = currentNow;
    }

    let tabs;
    try {
      tabs = await chrome.tabs.query({});
    } catch (error) {
      console.error("ChromeTabGC: failed to enumerate tabs", error);
      return;
    }

    const liveIds = new Set(tabs.map((tab) => Number(tab.id)));
    const activeIds = tabs.filter((tab) => tab.active).map((tab) => tab.id);
    const removedIds = new Set();

    for (const tab of tabs) {
      if (!isEligible(tab, state, idleMs, currentNow)) continue;

      let currentTab;
      try {
        currentTab = await chrome.tabs.get(tab.id);
      } catch (error) {
        console.error(`ChromeTabGC: failed to re-read tab ${tab.id}`, error);
        if (isMissingTabError(error)) {
          removedIds.add(Number(tab.id));
        }
        continue;
      }

      const latestState = await readSettledState(
        `failed to re-read state for tab ${tab.id}`,
      );
      if (!latestState) return;

      const revalidationState = {
        ...latestState,
        browserGraceAt: Math.max(latestState.browserGraceAt, state.browserGraceAt),
      };
      if (!isEligible(currentTab, revalidationState, idleMs, currentNow)) continue;

      try {
        await chrome.tabs.remove(tab.id);
        removedIds.add(Number(tab.id));
      } catch (error) {
        console.error(`ChromeTabGC: failed to remove tab ${tab.id}`, error);
      }
    }

    await mutateState((latestState) => {
      latestState.browserGraceAt = Math.max(
        latestState.browserGraceAt,
        state.browserGraceAt,
      );
      latestState.lastSweepAt = currentNow;
      for (const tabId of activeIds) {
        latestState.activityByTab[tabId] = Math.max(
          tabTimestamp(latestState.activityByTab, tabId),
          currentNow,
        );
      }
      latestState.activityByTab = pruneMap(
        latestState.activityByTab,
        liveIds,
        removedIds,
      );
      latestState.unpinnedAtByTab = pruneMap(
        latestState.unpinnedAtByTab,
        liveIds,
        removedIds,
      );
      return latestState;
    }, "failed to persist sweep state");
  }

  return { start, collect };
}

const ChromeTabGC = {
  DEFAULT_IDLE_MS,
  DEFAULT_ALARM_PERIOD_MINUTES,
  WAKE_GAP_MULTIPLIER,
  create,
};

globalThis.ChromeTabGC = ChromeTabGC;

if (typeof module !== "undefined") {
  module.exports = ChromeTabGC;
}
