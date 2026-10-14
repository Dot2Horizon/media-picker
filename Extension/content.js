// 페이지 안의 소리 나는 미디어 상태를 확장 백그라운드로 알리고, 재생·정지 명령을 받는다.
(() => {
  // 선언된 content script와 설치 직후 주입한 것이 겹치면 명령이 두 번 실행된다.
  if (window.__mediaPickerLoaded) return;
  window.__mediaPickerLoaded = true;

  const SELECTOR = 'video,audio';
  let lastPlayed = null;

  function candidates() {
    return [...document.querySelectorAll(SELECTOR)].filter((e) => e.duration > 0 && !e.muted);
  }

  function pick() {
    const media = candidates();
    return media.find((e) => !e.paused) || (media.includes(lastPlayed) ? lastPlayed : media[0]);
  }

  function report() {
    const media = pick();
    const state = media ? (media.paused ? 'paused' : 'playing') : 'none';
    const volume = media ? Math.round(media.volume * 100) : null;
    chrome.runtime.sendMessage({ type: 'media', state, volume }).catch(() => {});
  }

  for (const type of ['play', 'pause', 'ended', 'emptied', 'loadedmetadata', 'volumechange']) {
    document.addEventListener(type, (event) => {
      if (type === 'play') lastPlayed = event.target;
      report();
    }, true);
  }

  chrome.runtime.onMessage.addListener((message) => {
    if (message.type === 'probe') report();
    if (message.type !== 'command') return;
    if (message.action === 'pause') {
      document.querySelectorAll(SELECTOR).forEach((e) => e.pause());
    } else if (message.action === 'volume') {
      document.querySelectorAll(SELECTOR).forEach((e) => { e.volume = message.value / 100; });
    } else if (message.action === 'next' || message.action === 'previous') {
      mediaPickerSkip(message.action); // media-actions.js
    } else {
      const media = pick();
      if (media) media.play().catch(() => {});
    }
  });

  report();
})();
