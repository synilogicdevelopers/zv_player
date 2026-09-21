// The page run inside [YouTubeEngine]'s web view.
//
// YouTube's official IFrame Player API with its own controls switched off
// (`controls: 0`). ZV Player draws its controls over this surface and drives it
// through the API: playVideo/pauseVideo/seekTo/setVolume/mute/unMute/
// setPlaybackRate. Progress and state come back on the `ZvPlayerEvents`
// JavaScript channel as strings.

/// Builds the page for [videoId].
String youTubePage(
  String videoId, {
  required bool autoplay,
  required bool mute,
  Duration? startAt,
}) {
  return _template
      .replaceAll('__VIDEO_ID__', videoId)
      .replaceAll('__AUTOPLAY__', autoplay ? 'true' : 'false')
      .replaceAll('__MUTED__', mute ? 'true' : 'false')
      .replaceAll('__START_AT__', '${startAt?.inSeconds ?? 0}');
}

const String _template = r"""
<html><head><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="margin:0;padding:0;overflow:hidden;background:black;">
  <div id="player" style="width:100%;height:100%;position:relative;"></div>

  <script>
    console.warn = function(msg){
      if (msg && msg.toString().includes("web-share")) return;
    };
    console.error = function(msg){
      if (msg && msg.toString().includes("postMessage")) return;
    };

    var VIDEO_ID = "__VIDEO_ID__";
    var AUTOPLAY = __AUTOPLAY__;
    var MUTE = __MUTED__;
    var START_AT = __START_AT__;

  </script>

  <script>
    // The page's only way out: the host's `ZvPlayerEvents` JavaScript channel.
    function zvPost(message) {
      if (window.ZvPlayerEvents) window.ZvPlayerEvents.postMessage(message);
    }

    var player;

    function onYouTubeIframeAPIReady() {
      player = new YT.Player('player', {
        videoId: VIDEO_ID,
        playerVars: {
          autoplay: AUTOPLAY ? 1 : 0,
          mute: MUTE ? 1 : 0,
          controls: 0,
          disablekb: 1,
          iv_load_policy: 3,
          fs: 0,
          rel: 0,
          start: START_AT,
          playsinline: 1
        },
        events: {
          'onStateChange': onPlayerStateChange,
          'onReady': onPlayerReady,
          'onError': function(event) {
            zvPost(JSON.stringify({event: 'error', code: event.data}));
          }
        }
      });
    }

    function onPlayerReady() {
      // seekTo on a cued YouTube video starts playback. A paused reconnect
      // must cue its checkpoint instead, leaving the play decision to the user.
      if (START_AT > 0 && AUTOPLAY) player.seekTo(START_AT, true);
      else if (!AUTOPLAY) player.cueVideoById({videoId: VIDEO_ID, startSeconds: START_AT});
      // Publish duration immediately. Waiting for the first 'playing' event
      // left the progress bar with no total length to draw against.
      sendProgress();
      startTimer();
    }

    // One progress payload. Buffered, volume and rate are all genuinely
    // exposed by the IFrame API, so they are reported rather than guessed.
    function sendProgress() {
      if (!player || !player.getDuration || !window.ZvPlayerEvents) return;
      try {
        var msg = JSON.stringify({
          event: "timeUpdate",
          currentTime: player.getPlayerState() === 5 ? START_AT : player.getCurrentTime(),
          duration: player.getDuration(),
          buffered: player.getVideoLoadedFraction ? player.getVideoLoadedFraction() : null,
          volume: player.getVolume ? player.getVolume() / 100 : null,
          muted: player.isMuted ? player.isMuted() : null,
          rate: player.getPlaybackRate ? player.getPlaybackRate() : null
        });
        zvPost(msg);
      } catch (e) {}
    }

    function onPlayerStateChange(event) {
      if (!window.ZvPlayerEvents) return;

      if (event.data === 1) {
        zvPost("playing");
        startTimer();
      }
      else if (event.data === 2) {
        zvPost("paused");
        stopTimer();
      }
      else if (event.data === 0) {
        zvPost("ended");
        stopTimer();
      }
      else if (event.data === 3) {
        zvPost("buffering");
      }
      // CUED (5): the media is loaded but the provider is not playing it,
      // which is what an Android WebView leaves behind when it declines to
      // autoplay. Without this the host never leaves its 'loading' state, so
      // it shows a spinner instead of a play control and treats the video as
      // not yet seekable.
      //
      // UNSTARTED (-1) is deliberately NOT handled here. It fires during
      // ordinary start-up, before autoplay gets going, so reporting it as
      // cued mislabels a video that is about to play - and stopping the
      // progress timer there killed the one onPlayerReady had just started.
      else if (event.data === 5) {
        sendProgress();
        zvPost("cued");
      }
    }

    var intervalId;

    function startTimer() {
      stopTimer();
      intervalId = setInterval(sendProgress, 400);
    }

    function stopTimer() {
      if (intervalId) clearInterval(intervalId);
      intervalId = null;
    }

    function playVideo(){ player.playVideo(); }
    function pauseVideo(){ player.pauseVideo(); }
    // getCurrentTime() lags the seek request, so sampling it in the same tick
    // reports the *old* position and overwrites the host's optimistic update -
    // which looks exactly like a seek that did nothing. Sample once the player
    // has applied it, and again a little later, because a paused player has no
    // progress timer running to correct the value afterwards.
    function seekTo(sec){
      player.seekTo(sec, true);
      setTimeout(sendProgress, 120);
      setTimeout(sendProgress, 400);
    }
    function mute(){ player.mute(); sendProgress(); }

    // The Dart contract is 0..1 everywhere; YouTube's API wants 0..100.
    function setVolume(vol){
      player.setVolume(Math.round(Math.max(0, Math.min(1, vol)) * 100));
      sendProgress();
    }

    function setPlaybackRate(rate){
      if (player.setPlaybackRate) player.setPlaybackRate(rate);
      sendProgress();
    }

    // Unmuting must not start playback. This previously called playVideo(),
    // so tapping unmute while paused silently resumed the video. The IFrame
    // API restores the previous volume on unMute(), so it is not forced here.
    function unMute(){
      player.unMute();
      sendProgress();
    }

  </script>

  <!--
    Loaded only after onYouTubeIframeAPIReady exists. The API script injects
    www-widgetapi.js async and calls the callback as soon as it runs; with a
    warm cache (an inline trailer loaded it seconds earlier) that happened
    before the callback was defined, so the player was never created and the
    movie sat at 0:00 forever.
  -->
  <script src="https://www.youtube.com/iframe_api"></script>
</body>
</html>
""";
