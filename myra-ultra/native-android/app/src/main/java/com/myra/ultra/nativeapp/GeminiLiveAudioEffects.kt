package com.myra.ultra.nativeapp

import android.media.audiofx.AudioEffect
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor

/** Optional Android pre-processing for the Live microphone's AudioRecord session. */
internal object GeminiLiveAudioEffects {
    internal enum class Kind(val label: String) {
        ECHO_CANCELLATION("echo cancellation"),
        NOISE_SUPPRESSION("noise suppression"),
        AUTOMATIC_GAIN_CONTROL("automatic gain control"),
    }

    internal interface Handle {
        fun enable(): Boolean
        fun isEnabled(): Boolean
        fun release()
    }

    internal interface Factory {
        fun isAvailable(kind: Kind): Boolean
        fun create(kind: Kind, audioSessionId: Int): Handle?
    }

    internal class Active internal constructor(
        val enabledLabels: List<String>,
        private val handles: List<Handle>,
    ) : AutoCloseable {
        private var closed = false

        @Synchronized
        override fun close() {
            if (closed) return
            closed = true
            handles.forEach { handle -> try { handle.release() } catch (_: Exception) { } }
        }
    }

    /** Best-effort: unsupported or failing platform effects never prevent microphone capture. */
    internal fun attach(audioSessionId: Int, factory: Factory = AndroidFactory): Active {
        val handles = mutableListOf<Handle>()
        val enabled = mutableListOf<String>()
        Kind.values().forEach { kind ->
            val available = try { factory.isAvailable(kind) } catch (_: Exception) { false }
            if (!available) return@forEach
            val handle = try { factory.create(kind, audioSessionId) } catch (_: Exception) { null } ?: return@forEach
            val active = try { handle.enable() && handle.isEnabled() } catch (_: Exception) { false }
            if (active) {
                handles += handle
                enabled += kind.label
            } else {
                try { handle.release() } catch (_: Exception) { }
            }
        }
        return Active(enabled.toList(), handles.toList())
    }

    private object AndroidFactory : Factory {
        override fun isAvailable(kind: Kind): Boolean = when (kind) {
            Kind.ECHO_CANCELLATION -> AcousticEchoCanceler.isAvailable()
            Kind.NOISE_SUPPRESSION -> NoiseSuppressor.isAvailable()
            Kind.AUTOMATIC_GAIN_CONTROL -> AutomaticGainControl.isAvailable()
        }

        override fun create(kind: Kind, audioSessionId: Int): Handle? {
            val effect: AudioEffect? = when (kind) {
                Kind.ECHO_CANCELLATION -> AcousticEchoCanceler.create(audioSessionId)
                Kind.NOISE_SUPPRESSION -> NoiseSuppressor.create(audioSessionId)
                Kind.AUTOMATIC_GAIN_CONTROL -> AutomaticGainControl.create(audioSessionId)
            }
            return effect?.let(::AudioEffectHandle)
        }
    }

    private class AudioEffectHandle(private val effect: AudioEffect) : Handle {
        override fun enable(): Boolean = effect.setEnabled(true) == AudioEffect.SUCCESS
        override fun isEnabled(): Boolean = effect.enabled
        override fun release() = effect.release()
    }
}
