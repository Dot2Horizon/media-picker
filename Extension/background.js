// 탭별 미디어 상태를 모아 MediaPicker 앱(127.0.0.1)에 보내고, 앱의 명령을 탭에 전달한다.
const APP_URL = 'ws://127.0.0.1:17872';

/** tabId -> Map(frameId -> { state: 'playing' | 'paused', volume }) */
const frames = new Map();
let socket = null;
let pushTimer = null;

function browserName() {
  const brands = (navigator.userAgentData?.brands || []).map((b) => b.brand).join(' ');
  if (/Edge/.test(brands)) return 'Edge';
  if (/Brave/.test(brands)) return 'Brave';
  if (/Opera/.test(brands)) return 'Opera';
  return 'Chrome';
}

function tabInfo(tabId) {
  const infos = [...(frames.get(tabId)?.values() || [])];
  return infos.find((i) => i.state === 'playing') || infos.find((i) => i.state === 'paused') || null;
}

function tabState(tabId) {
  return tabInfo(tabId)?.state || null;
}

async function pushState() {
  if (socket?.readyState !== WebSocket.OPEN) return;
  const tabs = [];
  // 영상/오디오 요소 없이 소리를 내는 탭(번역기 음성, Web Audio 등)도 크롬은 audible로 알려준다.
  const audible = await chrome.tabs.query({ audible: true });
  for (const tab of audible) {
    if (tabState(tab.id)) continue;
    // 음소거해도 audible은 남는다. 우리가 음소거한 탭은 '정지'로 보여준다.
    const state = mutedByUs.has(tab.id) ? 'paused' : 'playing';
    tabs.push({ id: tab.id, title: tab.title || '', url: tab.url || '', state, volume: null });
  }
  for (const tabId of frames.keys()) {
    const info = tabInfo(tabId);
    if (!info) continue;
    try {
      const tab = await chrome.tabs.get(tabId);
      tabs.push({ id: tabId, title: tab.title || '', url: tab.url || '', state: info.state, volume: info.volume });
    } catch {
      frames.delete(tabId);
    }
  }
  socket.send(JSON.stringify({ type: 'state', tabs }));
}

function schedulePush() {
  clearTimeout(pushTimer);
  pushTimer = setTimeout(pushState, 100);
}

function connect() {
  if (socket && socket.readyState <= WebSocket.OPEN) return;
  socket = new WebSocket(APP_URL);
  socket.onopen = () => {
    socket.send(JSON.stringify({ type: 'hello', browser: browserName() }));
    pushState();
  };
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.type === 'command') runCommand(message.tabId, message.action, message.value);
  };
  socket.onclose = () => {
    socket = null;
    setTimeout(connect, 3000);
  };
  socket.onerror = () => {};
}

/** 정지가 안 먹혀 우리가 음소거한 탭. 다시 재생할 때 음소거를 푼다. */
const mutedByUs = new Set();

async function runCommand(tabId, action, value) {
  if (action === 'play' && mutedByUs.has(tabId)) {
    mutedByUs.delete(tabId);
    chrome.tabs.update(tabId, { muted: false }).catch(() => {});
  }
  chrome.tabs.sendMessage(tabId, { type: 'command', action, value }).catch(() => {});
  if (action !== 'pause') return;
  // 영상/오디오 요소가 아닌 소리(Web Audio 등)는 멈출 수 없다. 계속 소리가 나면 탭을 음소거한다.
  // audible은 소리가 멈춘 뒤에도 2초쯤 남으므로 충분히 기다리고, 요소가 멈춘 탭은 건너뛴다.
  setTimeout(async () => {
    const tab = await chrome.tabs.get(tabId).catch(() => null);
    if (tab?.audible && !tab.mutedInfo?.muted && tabState(tabId) !== 'paused') {
      mutedByUs.add(tabId);
      await chrome.tabs.update(tabId, { muted: true }).catch(() => {});
      schedulePush();
    }
  }, 3000);
}

// 서비스 워커가 새로 깨어나면 상태를 잃으므로 모든 탭에 다시 물어본다.
async function probeAll() {
  for (const tab of await chrome.tabs.query({})) {
    chrome.tabs.sendMessage(tab.id, { type: 'probe' }).catch(() => {});
  }
}

chrome.runtime.onMessage.addListener((message, sender) => {
  if (message.type !== 'media' || !sender.tab) return;
  const tabId = sender.tab.id;
  if (!frames.has(tabId)) frames.set(tabId, new Map());
  if (message.state === 'none') frames.get(tabId).delete(sender.frameId);
  else frames.get(tabId).set(sender.frameId, { state: message.state, volume: message.volume });
  schedulePush();
});

chrome.tabs.onRemoved.addListener((tabId) => {
  frames.delete(tabId);
  schedulePush();
});

chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (change.status === 'loading') frames.delete(tabId);
  if ('audible' in change) schedulePush();
  if (frames.has(tabId) && (change.title || change.url)) schedulePush();
});

// 확장을 설치·새로고침하기 전부터 열려 있던 탭에는 살아 있는 content script가 없다.
// 물어봐서 대답이 없는 탭에만 넣는다(겹치면 명령이 두 번 실행된다).
async function injectExistingTabs() {
  for (const tab of await chrome.tabs.query({ url: ['http://*/*', 'https://*/*'] })) {
    const alive = await chrome.tabs.sendMessage(tab.id, { type: 'ping' }).then(() => true, () => false);
    if (alive) continue;
    chrome.scripting.executeScript({
      target: { tabId: tab.id, allFrames: true },
      files: ['media-actions.js', 'content.js'],
    }).catch(() => {});
  }
}
chrome.runtime.onInstalled.addListener(injectExistingTabs);
chrome.runtime.onStartup.addListener(injectExistingTabs);

// 앱이 나중에 켜져도 다시 붙도록 주기적으로 깨운다.
chrome.alarms.create('reconnect', { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(connect);

connect();
probeAll();
