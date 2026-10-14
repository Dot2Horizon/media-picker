// 탭 안에서 다음/이전을 처리한다.
// 확장(content script)과 앱의 AppleScript 경로가 이 파일 하나를 함께 쓴다.
var mediaPickerSkip = function (direction) {
  const media = [...document.querySelectorAll('video,audio')].filter((e) => e.duration > 0 && !e.muted);
  const current = media.find((e) => !e.paused) || media[0];
  const host = location.hostname;

  const click = (selector) => {
    const button = document.querySelector(selector);
    if (!button || button.disabled || button.getClientRects().length === 0) return false;
    button.click();
    return true;
  };

  // 넷플릭스는 currentTime을 직접 바꾸면 재생 오류가 나서 버튼만 쓴다.
  if (host.endsWith('netflix.com')) {
    return direction === 'next' && click('[data-uia="control-next"]') ? 'next' : 'none';
  }

  if (host.endsWith('youtube.com')) {
    if (direction === 'next') {
      return click('.ytp-next-button') || click('ytmusic-player-bar .next-button') ? 'next' : 'none';
    }
    // 이전: 3초 넘게 들었으면 처음으로, 아니면 이전 곡 (Spotify와 같은 방식)
    if (current && current.currentTime > 3) {
      current.currentTime = 0;
      return 'restart';
    }
    if (click('.ytp-prev-button') || click('ytmusic-player-bar .previous-button')) return 'previous';
    if (current) current.currentTime = 0;
    return 'restart';
  }

  // 그 밖의 사이트: 10초 앞/뒤로
  if (!current) return 'none';
  const delta = direction === 'next' ? 10 : -10;
  current.currentTime = Math.max(0, Math.min(current.duration, current.currentTime + delta));
  return 'seek';
};
