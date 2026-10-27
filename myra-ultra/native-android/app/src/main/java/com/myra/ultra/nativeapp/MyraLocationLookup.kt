package com.myra.ultra.nativeapp

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import kotlin.coroutines.resume

/** A transient coarse location result. Callers must not persist it; external transfer needs a separate explicit user confirmation. */
data class MyraLocationFix(
    val latitude: Double,
    val longitude: Double,
    val accuracyMeters: Float?,
    val capturedAtMillis: Long,
) {
    fun coordinates(): String = String.format(Locale.US, "%.5f, %.5f", latitude, longitude)

    /** A geo URI to hand to a Maps app only after a separate user tap. */
    fun mapsUri(): String = "geo:$latitude,$longitude?q=$latitude,$longitude"

    companion object {
        fun create(latitude: Double, longitude: Double, accuracyMeters: Float?, capturedAtMillis: Long): MyraLocationFix? {
            if (!latitude.isFinite() || latitude !in -90.0..90.0) return null
            if (!longitude.isFinite() || longitude !in -180.0..180.0) return null
            val accuracy = accuracyMeters?.takeIf { it.isFinite() && it >= 0f }
            return MyraLocationFix(latitude, longitude, accuracy, capturedAtMillis.coerceAtLeast(0L))
        }

        fun from(location: Location): MyraLocationFix? = create(
            location.latitude,
            location.longitude,
            if (location.hasAccuracy()) location.accuracy else null,
            location.time,
        )
    }
}

object MyraLocationLookup {
    const val TIMEOUT_MILLIS = 20_000L

    /** Requests one current fix after the UI has obtained ACCESS_COARSE_LOCATION. */
    suspend fun currentLocation(context: Context): MyraLocationFix? = withContext(Dispatchers.Main.immediate) {
        if (context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            throw SecurityException("Coarse location permission is required.")
        }
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: throw IllegalStateException("Android location service is unavailable.")
        val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
        val provider = providers.firstOrNull { name ->
            try { manager.isProviderEnabled(name) } catch (_: Exception) { false }
        } ?: throw IllegalStateException("Turn on Android location services and try again.")

        val location = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            withTimeoutOrNull(TIMEOUT_MILLIS) {
                suspendCancellableCoroutine<Location?> { continuation ->
                    val cancellation = CancellationSignal()
                    continuation.invokeOnCancellation { cancellation.cancel() }
                    try {
                        manager.getCurrentLocation(provider, cancellation, context.mainExecutor) { result ->
                            if (continuation.isActive) continuation.resume(result)
                        }
                    } catch (error: SecurityException) {
                        if (continuation.isActive) continuation.resumeWith(Result.failure(error))
                    } catch (error: Exception) {
                        if (continuation.isActive) continuation.resume(null)
                    }
                }
            }
        } else {
            legacyOneShot(manager, provider)
        }
        location?.let(MyraLocationFix::from)
    }

    @Suppress("DEPRECATION")
    private suspend fun legacyOneShot(manager: LocationManager, provider: String): Location? =
        withTimeoutOrNull(TIMEOUT_MILLIS) {
            suspendCancellableCoroutine { continuation ->
                val handler = Handler(Looper.getMainLooper())
                var completed = false
                lateinit var listener: LocationListener
                lateinit var timeout: Runnable
                fun finish(location: Location?) {
                    if (completed) return
                    completed = true
                    handler.removeCallbacks(timeout)
                    try { manager.removeUpdates(listener) } catch (_: Exception) { }
                    if (continuation.isActive) continuation.resume(location)
                }
                timeout = Runnable { finish(null) }
                listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) = finish(location)
                    override fun onProviderDisabled(providerName: String) = finish(null)
                    override fun onProviderEnabled(providerName: String) = Unit
                    override fun onStatusChanged(providerName: String?, status: Int, extras: android.os.Bundle?) = Unit
                }
                continuation.invokeOnCancellation {
                    handler.removeCallbacks(timeout)
                    try { manager.removeUpdates(listener) } catch (_: Exception) { }
                }
                try {
                    manager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
                    handler.postDelayed(timeout, TIMEOUT_MILLIS)
                } catch (error: SecurityException) {
                    if (continuation.isActive) continuation.resumeWith(Result.failure(error))
                } catch (_: Exception) {
                    finish(null)
                }
            }
        }
}
