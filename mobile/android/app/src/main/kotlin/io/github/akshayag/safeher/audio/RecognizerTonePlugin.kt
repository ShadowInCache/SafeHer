package io.github.akshayag.safeher.audio

import android.content.Context
import android.content.SharedPreferences
import android.media.AudioManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Silences the beep Android plays whenever speech recognition starts or stops.
 *
 * The tone comes from the system recognition service, not from this app and
 * not from the `speech_to_text` plugin — there is no Dart-side option that
 * turns it off. The only lever is the stream it plays on.
 *
 * It is unbearable here specifically because of how the monitor listens. A
 * recognition session ends after a few seconds of silence, and the monitor
 * immediately opens another, so a quiet walk produces a beep roughly every
 * four seconds for the length of the journey.
 *
 * ## What is muted, and what deliberately is not
 *
 * Muted: `STREAM_MUSIC`, `STREAM_SYSTEM`, `STREAM_NOTIFICATION`. Which of
 * these carries the tone varies by OEM and Android version, so all three go.
 *
 * **Never muted: `STREAM_RING` and `STREAM_ALARM`.** Those carry incoming
 * calls and the user's alarms. Silencing an incoming call on a woman walking
 * home alone — possibly the call from the contact this app just alerted — to
 * save a beep would be a straight downgrade in safety. The tone is annoying;
 * a missed emergency call is not a trade worth making.
 *
 * Muting `STREAM_MUSIC` does mean music and podcasts are silenced for the
 * duration of a journey. That is a real cost, and it is the one the tone
 * forces: the beep plays on that stream on many devices, and a beep every
 * four seconds would drown the music anyway.
 *
 * ## Surviving a crash
 *
 * A stream muted by this plugin and never unmuted would leave the phone
 * silent after the app closed, which the user could only fix by hunting
 * through volume settings. So the muted state is written to disk before the
 * mute is applied and cleared after it is lifted; if the flag is still set
 * when the plugin next attaches, the app died while muted and the streams are
 * restored then. Only streams this plugin muted are ever unmuted — a stream
 * the user silenced themselves is left alone.
 *
 * Requires `MODIFY_AUDIO_SETTINGS`, a normal permission granted at install.
 */
class RecognizerTonePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "io.github.akshayag.safeher/recognizer_tone"
        private const val PREFS = "safeher_recognizer_tone"
        private const val KEY_MUTED = "streams_muted"

        /**
         * Ring and alarm are absent by design — see the class comment. Do not
         * add them.
         */
        private val MUTED_STREAMS = intArrayOf(
            AudioManager.STREAM_MUSIC,
            AudioManager.STREAM_SYSTEM,
            AudioManager.STREAM_NOTIFICATION,
        )
    }

    private var channel: MethodChannel? = null
    private var audioManager: AudioManager? = null
    private var prefs: SharedPreferences? = null
    private var muted = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
            .also { it.setMethodCallHandler(this) }
        val context = binding.applicationContext
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        // The app died while muted last time. Put the phone back as we found it.
        if (prefs?.getBoolean(KEY_MUTED, false) == true) {
            muted = true
            unmute()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Leaving the phone silent because the engine went away is not an
        // option, so this runs before anything else is torn down.
        unmute()
        channel?.setMethodCallHandler(null)
        channel = null
        audioManager = null
        prefs = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "mute" -> result.success(mute())
            "unmute" -> {
                unmute()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Returns whether the streams are now muted. */
    private fun mute(): Boolean {
        if (muted) return true
        val manager = audioManager ?: return false

        // Recorded first: a crash between the write and the adjust leaves a
        // flag with nothing muted, which costs one harmless unmute next
        // launch. The reverse order could leave the phone silent for good.
        prefs?.edit()?.putBoolean(KEY_MUTED, true)?.apply()

        var any = false
        for (stream in MUTED_STREAMS) {
            if (adjust(manager, stream, AudioManager.ADJUST_MUTE)) any = true
        }

        if (!any) {
            prefs?.edit()?.putBoolean(KEY_MUTED, false)?.apply()
            return false
        }
        muted = true
        return true
    }

    private fun unmute() {
        if (!muted) return
        val manager = audioManager
        if (manager != null) {
            for (stream in MUTED_STREAMS) {
                adjust(manager, stream, AudioManager.ADJUST_UNMUTE)
            }
        }
        muted = false
        prefs?.edit()?.putBoolean(KEY_MUTED, false)?.apply()
    }

    private fun adjust(manager: AudioManager, stream: Int, direction: Int): Boolean = try {
        manager.adjustStreamVolume(stream, direction, 0)
        true
    } catch (error: SecurityException) {
        // Do Not Disturb is on and this app is not allowed to change volume.
        // Nothing to undo; the beep stays, which is the lesser failure.
        false
    } catch (error: RuntimeException) {
        false
    }
}
