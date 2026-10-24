@file:OptIn(UnstableApi::class)

package dev.chithram.player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.SurfaceView
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.ui.SubtitleView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * One ExoPlayer plus its Flutter event stream. Everything runs on the main thread.
 * The log lines starting with CHITHRAM_ are what CI asserts on.
 */
class PlayerHost(
    private val context: Context,
    val id: Int,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val events = EventChannel(messenger, "chithram_player/events/$id")
    private var sink: EventChannel.EventSink? = null
    private var released = false

    // Small buffers for a fast start: begin after 0.5 s buffered, resume after 1.5 s.
    private val loadControl = DefaultLoadControl.Builder()
        .setBufferDurationsMs(5_000, 30_000, 500, 1_500)
        .build()

    private val player: ExoPlayer = ExoPlayer.Builder(context)
        .setLoadControl(loadControl)
        .build()

    private var openStartMs = 0L
    private var firstFrameLogged = false
    private var durationLogged = false
    private var pendingSeekTarget = -1L
    private var surfaceView: SurfaceView? = null
    private var subtitleView: SubtitleView? = null

    // Applied on each open (see setPreferences).
    private var preferredAudio: String? = null
    private var preferredText: String? = null
    private var textOn = false

    private val ticker = object : Runnable {
        override fun run() {
            if (released) return
            tick()
            main.postDelayed(this, 250)
        }
    }

    init {
        events.setStreamHandler(this)
        player.addListener(object : Player.Listener {
            override fun onRenderedFirstFrame() {
                if (firstFrameLogged) return
                firstFrameLogged = true
                Log.i(TAG, "CHITHRAM_FIRST_FRAME ${SystemClock.elapsedRealtime() - openStartMs}")
            }

            override fun onPlaybackStateChanged(state: Int) {
                Log.i(TAG, "CHITHRAM_STATE ${stateName(state)}")
                updateKeepScreenOn()
                maybeLogDuration()
            }

            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                Log.i(TAG, "CHITHRAM_PLAY_WHEN_READY $playWhenReady")
                updateKeepScreenOn()
            }

            override fun onTimelineChanged(timeline: androidx.media3.common.Timeline, reason: Int) {
                maybeLogDuration()
            }

            override fun onTracksChanged(tracks: Tracks) {
                val v = tracks.groups.count { it.type == C.TRACK_TYPE_VIDEO && it.isSelected }
                val a = tracks.groups.count { it.type == C.TRACK_TYPE_AUDIO && it.isSelected }
                Log.i(TAG, "CHITHRAM_TRACKS video=$v audio=$a")
                sendTracks(tracks)
            }

            override fun onCues(cueGroup: CueGroup) {
                subtitleView?.setCues(cueGroup.cues)
            }

            override fun onPositionDiscontinuity(
                oldPosition: Player.PositionInfo,
                newPosition: Player.PositionInfo,
                reason: Int,
            ) {
                if (reason == Player.DISCONTINUITY_REASON_SEEK) {
                    pendingSeekTarget = newPosition.positionMs
                    Log.i(TAG, "CHITHRAM_SEEK_START to=${newPosition.positionMs}")
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.e(TAG, "CHITHRAM_ERROR ${error.errorCodeName}: ${error.message}", error)
                sink?.success(mapOf("t" to "error", "message" to "${error.errorCodeName}: ${error.message}"))
            }
        })
        main.post(ticker)
    }

    private fun stateName(s: Int) = when (s) {
        Player.STATE_IDLE -> "idle"
        Player.STATE_BUFFERING -> "buffering"
        Player.STATE_READY -> "ready"
        Player.STATE_ENDED -> "ended"
        else -> "?"
    }

    private fun maybeLogDuration() {
        if (durationLogged || player.playbackState == Player.STATE_IDLE) return
        val d = player.duration
        if (d != C.TIME_UNSET && !player.isCurrentMediaItemLive) {
            durationLogged = true
            Log.i(TAG, "CHITHRAM_DURATION $d")
        }
    }

    private fun tick() {
        // A seek counts as complete once playing resumes at or after its target.
        if (pendingSeekTarget >= 0 && player.playbackState == Player.STATE_READY && player.isPlaying &&
            player.currentPosition >= pendingSeekTarget
        ) {
            Log.i(TAG, "CHITHRAM_SEEK_DONE target=$pendingSeekTarget pos=${player.currentPosition}")
            pendingSeekTarget = -1
        }
        sink?.success(
            mapOf(
                "t" to "state",
                "pos" to player.currentPosition,
                "dur" to (if (player.duration == C.TIME_UNSET) 0L else player.duration),
                "buf" to player.bufferedPosition,
                "ended" to (player.playbackState == Player.STATE_ENDED),
                "buffering" to (player.playbackState == Player.STATE_BUFFERING),
                "playing" to player.playWhenReady,
            ),
        )
    }

    /** Audio and text tracks as maps for the `tracks` event; ids are "group:track". */
    private fun trackList(tracks: Tracks, type: Int): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        tracks.groups.forEachIndexed { g, group ->
            if (group.type != type) return@forEachIndexed
            for (i in 0 until group.length) {
                if (!group.isTrackSupported(i)) continue
                val f = group.getTrackFormat(i)
                out.add(
                    mapOf(
                        "id" to "$g:$i",
                        "lang" to f.language,
                        "label" to f.label,
                        "mime" to f.sampleMimeType,
                        "codecs" to f.codecs,
                        "ch" to (if (f.channelCount == Format.NO_VALUE) null else f.channelCount),
                        "sel" to group.isTrackSelected(i),
                        "def" to ((f.selectionFlags and C.SELECTION_FLAG_DEFAULT) != 0),
                        "forced" to ((f.selectionFlags and C.SELECTION_FLAG_FORCED) != 0),
                    ),
                )
            }
        }
        return out
    }

    private fun sendTracks(tracks: Tracks) {
        sink?.success(
            mapOf(
                "t" to "tracks",
                "audio" to trackList(tracks, C.TRACK_TYPE_AUDIO),
                "text" to trackList(tracks, C.TRACK_TYPE_TEXT),
            ),
        )
    }

    /** [kind] is "audio" or "text"; a null [trackId] turns that type off. */
    fun selectTrack(kind: String, trackId: String?) {
        val type = if (kind == "audio") C.TRACK_TYPE_AUDIO else C.TRACK_TYPE_TEXT
        val params = player.trackSelectionParameters.buildUpon()
        if (trackId == null) {
            params.clearOverridesOfType(type).setTrackTypeDisabled(type, true)
        } else {
            val parts = trackId.split(':')
            val g = parts.getOrNull(0)?.toIntOrNull() ?: return
            val i = parts.getOrNull(1)?.toIntOrNull() ?: return
            val group = player.currentTracks.groups.getOrNull(g) ?: return
            if (group.type != type || i >= group.length) return
            params.setTrackTypeDisabled(type, false)
                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, i))
        }
        player.trackSelectionParameters = params.build()
        Log.i(TAG, "CHITHRAM_SELECT_TRACK $kind=${trackId ?: "off"}")
    }

    /** What the next [open] picks: preferred languages, subtitles on or off. */
    fun setPreferences(audioLanguage: String?, textLanguage: String?, text: Boolean) {
        preferredAudio = audioLanguage
        preferredText = textLanguage
        textOn = text
    }

    fun open(videoUrl: String, audioUrl: String?, headers: Map<String, String>, isLive: Boolean, startMs: Long) {
        openStartMs = SystemClock.elapsedRealtime()
        firstFrameLogged = false
        durationLogged = false
        pendingSeekTarget = -1
        // A new item: earlier picks do not carry over, the preferences do.
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .clearOverrides()
            .setPreferredAudioLanguage(preferredAudio)
            .setPreferredTextLanguage(preferredText)
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, !textOn)
            .build()

        val http = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setDefaultRequestProperties(headers)
        headers.entries.firstOrNull { it.key.equals("User-Agent", ignoreCase = true) }
            ?.let { http.setUserAgent(it.value) }
        val factory = DefaultMediaSourceFactory(DefaultDataSource.Factory(context, http))

        fun source(url: String): MediaSource {
            val item = MediaItem.Builder().setUri(url)
            if (isLive) {
                item.setLiveConfiguration(
                    MediaItem.LiveConfiguration.Builder()
                        .setTargetOffsetMs(6_000)
                        .setMinPlaybackSpeed(0.97f)
                        .setMaxPlaybackSpeed(1.03f)
                        .build(),
                )
            }
            return factory.createMediaSource(item.build())
        }

        // Separate video and audio (YouTube DASH): MergingMediaSource plays both together.
        val media = if (audioUrl.isNullOrEmpty()) source(videoUrl)
        else MergingMediaSource(source(videoUrl), source(audioUrl))

        player.setMediaSource(media, startMs)
        player.prepare()
        player.playWhenReady = true
        // Hosts only: playlist URLs can carry credentials, and logcat is readable.
        Log.i(TAG, "CHITHRAM_OPEN video=${hostOf(videoUrl)} audio=${audioUrl?.let(::hostOf)} live=$isLive")
    }

    fun play() { player.playWhenReady = true }
    fun pause() { player.playWhenReady = false }
    fun seek(ms: Long) { player.seekTo(ms) }

    fun attach(view: SurfaceView, subtitles: SubtitleView) {
        if (released) return
        surfaceView = view
        subtitleView = subtitles
        subtitles.setCues(player.currentCues.cues)
        updateKeepScreenOn()
        player.setVideoSurfaceView(view)
    }

    fun detach(view: SurfaceView) {
        if (surfaceView === view) {
            surfaceView = null
            subtitleView = null
        }
        if (!released) player.clearVideoSurfaceView(view)
    }

    // Keeps the TV screensaver off while the video plays or is about to.
    private fun updateKeepScreenOn() {
        val state = player.playbackState
        surfaceView?.keepScreenOn = player.playWhenReady &&
            (state == Player.STATE_READY || state == Player.STATE_BUFFERING)
    }

    private fun hostOf(url: String): String =
        try {
            val u = Uri.parse(url)
            if (u.host.isNullOrEmpty()) "<invalid url>" else "${u.scheme}://${u.host}"
        } catch (e: Exception) {
            "<invalid url>"
        }

    fun release() {
        if (released) return
        released = true
        main.removeCallbacks(ticker)
        events.setStreamHandler(null)
        sink = null
        player.release()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    companion object {
        private const val TAG = "ChithramPlayer"
    }
}
