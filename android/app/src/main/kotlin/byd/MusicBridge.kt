package byd

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MusicNotificationListenerService : android.service.notification.NotificationListenerService() {
    override fun onListenerConnected() {
        super.onListenerConnected()
        MusicBridge.refreshFromNotificationListener()
    }

    override fun onNotificationPosted(sbn: android.service.notification.StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        MusicBridge.refreshFromNotificationListener()
    }

    override fun onNotificationRemoved(sbn: android.service.notification.StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        MusicBridge.refreshFromNotificationListener()
    }
}

object MusicBridge {
    private const val METHOD_CHANNEL = "byd/music"
    private const val EVENT_CHANNEL = "byd/music/events"

    private lateinit var appContext: Context
    private var eventSink: EventChannel.EventSink? = null
    private var activeController: MediaController? = null

    private val controllerCallback =
        object : MediaController.Callback() {
            override fun onMetadataChanged(metadata: MediaMetadata?) {
                emitCurrentState()
            }

            override fun onPlaybackStateChanged(state: PlaybackState?) {
                emitCurrentState()
            }

            override fun onSessionDestroyed() {
                activeController?.unregisterCallback(this)
                activeController = null
                emitCurrentState()
            }
        }

    fun register(binaryMessenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext

        MethodChannel(binaryMessenger, METHOD_CHANNEL).setMethodCallHandler(::handleMethodCall)
        EventChannel(binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    emitCurrentState()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
    }

    fun refreshFromNotificationListener() {
        if (::appContext.isInitialized) {
            emitCurrentState()
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getState" -> result.success(currentStateMap())
            "playPause" -> {
                val controller = selectController()
                val state = controller?.playbackState?.state
                if (state == PlaybackState.STATE_PLAYING || state == PlaybackState.STATE_BUFFERING) {
                    controller?.transportControls?.pause()
                } else {
                    controller?.transportControls?.play()
                }
                result.success(currentStateMap())
            }
            "play" -> {
                selectController()?.transportControls?.play()
                result.success(currentStateMap())
            }
            "pause" -> {
                selectController()?.transportControls?.pause()
                result.success(currentStateMap())
            }
            "next" -> {
                selectController()?.transportControls?.skipToNext()
                result.success(currentStateMap())
            }
            "previous" -> {
                selectController()?.transportControls?.skipToPrevious()
                result.success(currentStateMap())
            }
            "openNotificationListenerSettings" -> {
                val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                appContext.startActivity(intent)
                result.success(null)
            }
            "openMusicApp" -> {
                result.success(openMusicApp())
            }
            else -> result.notImplemented()
        }
    }

    private fun emitCurrentState() {
        eventSink?.success(currentStateMap())
    }

    private fun currentStateMap(): Map<String, Any?> {
        val hasPermission = isNotificationListenerEnabled()
        val controller = selectController()
        val metadata = controller?.metadata
        val playbackState = controller?.playbackState
        val actions = playbackState?.actions ?: 0L
        val state = playbackState?.state

        return mapOf(
            "hasPermission" to hasPermission,
            "hasController" to (controller != null),
            "packageName" to controller?.packageName,
            "title" to metadata?.getString(MediaMetadata.METADATA_KEY_TITLE),
            "artist" to metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST),
            "album" to metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM),
            "durationMs" to metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION),
            "positionMs" to playbackState?.position,
            "updatedAtMs" to playbackState?.lastPositionUpdateTime,
            "canOpenMusicApp" to true,
            "isPlaying" to (
                state == PlaybackState.STATE_PLAYING ||
                    state == PlaybackState.STATE_BUFFERING ||
                    state == PlaybackState.STATE_CONNECTING
                ),
            "canPlay" to hasAction(actions, PlaybackState.ACTION_PLAY),
            "canPause" to hasAction(actions, PlaybackState.ACTION_PAUSE),
            "canSkipNext" to hasAction(actions, PlaybackState.ACTION_SKIP_TO_NEXT),
            "canSkipPrevious" to hasAction(actions, PlaybackState.ACTION_SKIP_TO_PREVIOUS),
            "albumArt" to bitmapToPng(
                metadata?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                    ?: metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART),
            ),
            "elapsedRealtimeMs" to SystemClock.elapsedRealtime(),
        )
    }

    private fun openMusicApp(): Boolean {
        val activePackage = selectController()?.packageName
        val launchIntent = activePackage?.let {
            appContext.packageManager.getLaunchIntentForPackage(it)
        }

        val intent = launchIntent ?: Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_APP_MUSIC)
        }

        return try {
            appContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun selectController(): MediaController? {
        if (!isNotificationListenerEnabled()) {
            setActiveController(null)
            return null
        }

        val manager = appContext.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        val component = ComponentName(appContext, MusicNotificationListenerService::class.java)
        val controllers =
            try {
                manager.getActiveSessions(component)
            } catch (_: SecurityException) {
                emptyList()
            }

        val selected = controllers.firstOrNull {
            it.playbackState?.state == PlaybackState.STATE_PLAYING
        } ?: controllers.firstOrNull()

        setActiveController(selected)
        return selected
    }

    private fun setActiveController(controller: MediaController?) {
        if (activeController?.sessionToken == controller?.sessionToken) return
        activeController?.unregisterCallback(controllerCallback)
        activeController = controller
        activeController?.registerCallback(controllerCallback)
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            appContext.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return enabled.split(":").any {
            ComponentName.unflattenFromString(it)?.packageName == appContext.packageName
        }
    }

    private fun hasAction(actions: Long, action: Long): Boolean = actions and action != 0L

    private fun bitmapToPng(bitmap: Bitmap?): ByteArray? {
        if (bitmap == null) return null
        return ByteArrayOutputStream().use { stream ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 92, stream)
            stream.toByteArray()
        }
    }
}
