// 탭별 미디어 상태를 모아 MediaPicker 앱(127.0.0.1)에 보내고, 앱의 명령을 탭에 전달한다.
const APP_URL = 'ws://127.0.0.1:17872';

/** tabId -> Map(frameId -> 'playing' | 'paused') */
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

function tabState(tabId) {
  const states = [...(frames.get(tabId)?.values() || [])];
  if (states.includes('playing')) return 'playing';
  if (states.includes('paused')) return 'paused';
  return null;
}

async function pushState() {
  if (socket?.readyState !== WebSocket.OPEN) return;
  const tabs = [];
  for (const tabId of frames.keys()) {
    const state = tabState(tabId);
    if (!state) continue;
    try {
      const tab = await chrome.tabs.get(tabId);
      tabs.push({ id: tabId, title: tab.title || '', url: tab.url || '', state });
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
    if (message.type === 'command') {
      chrome.tabs.sendMessage(message.tabId, { type: 'command', action: message.action }).catch(() => {});
    }
  };
  socket.onclose = () => {
    socket = null;
    setTimeout(connect, 3000);
  };
  socket.onerror = () => {};
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
  else frames.get(tabId).set(sender.frameId, message.state);
  schedulePush();
});

chrome.tabs.onRemoved.addListener((tabId) => {
  frames.delete(tabId);
  schedulePush();
});

chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (change.status === 'loading') frames.delete(tabId);
  if (frames.has(tabId) && (change.title || change.url)) schedulePush();
});

// 앱이 나중에 켜져도 다시 붙도록 주기적으로 깨운다.
chrome.alarms.create('reconnect', { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(connect);

connect();
probeAll();
