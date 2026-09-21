package com.synilogic.zv_player

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaCodecList
import android.media.MediaDrm
import android.os.Build
import android.util.DisplayMetrics
import android.view.Display
import android.view.WindowManager
import java.util.UUID

/**
 * Reports what this device can actually do.
 *
 * Everything here is measured - decoder capabilities, display HDR types, DRM
 * scheme support - rather than inferred from the model or the OS version. A
 * capability the device does not report is reported as absent, so the UI never
 * offers 4K or Dolby on hardware that cannot deliver it.
 */
object ZvCapabilities {

    private val WIDEVINE_UUID = UUID(-0x121074568629b532L, -0x5c37d8232ae2de13L)

    /**
     * Cached because the answer cannot change while the process lives, and
     * computing it is expensive: [MediaCodecList] enumeration plus
     * `getCapabilitiesForType` for every decoder takes hundreds of milliseconds
     * on mid-range hardware. Running that on the main thread during player
     * creation was measured as a ~1s frame stall.
     */
    @Volatile
    private var cached: Map<String, Any?>? = null

    /** Returns the cached probe, or null when it has not been computed yet. */
    fun cachedOrNull(): Map<String, Any?>? = cached

    fun probe(context: Context): Map<String, Any?> {
        cached?.let { return it }
        return probeUncached(context).also { cached = it }
    }

    private fun probeUncached(context: Context): Map<String, Any?> {
        val videoCodecs = mutableSetOf<String>()
        val audioCodecs = mutableSetOf<String>()
        var maxHeight = 0

        try {
            val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            for (info in codecList.codecInfos) {
                if (info.isEncoder) continue
                for (type in info.supportedTypes) {
                    val lower = type.lowercase()
                    when {
                        lower.startsWith("video/") -> {
                            videoCodecs.add(lower)
                            runCatching {
                                val heights = info.getCapabilitiesForType(type)
                                    .videoCapabilities
                                    ?.supportedHeights
                                    ?.upper ?: 0
                                if (heights > maxHeight) maxHeight = heights
                            }
                        }

                        lower.startsWith("audio/") -> audioCodecs.add(lower)
                    }
                }
            }
        } catch (_: Exception) {
            // A codec list that cannot be read leaves capabilities unknown
            // rather than optimistically assumed.
        }

        val hdrFormats = mutableSetOf<String>()
        var supportsHdr = false
        try {
            val display = currentDisplay(context)
            @Suppress("DEPRECATION")
            val hdrCapabilities = display?.hdrCapabilities
            hdrCapabilities?.supportedHdrTypes?.forEach { type ->
                when (type) {
                    Display.HdrCapabilities.HDR_TYPE_HDR10 -> hdrFormats.add("hdr10")
                    Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS -> hdrFormats.add("hdr10Plus")
                    Display.HdrCapabilities.HDR_TYPE_HLG -> hdrFormats.add("hlg")
                    Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> hdrFormats.add("dolbyVision")
                }
            }
            supportsHdr = hdrFormats.isNotEmpty()
        } catch (_: Exception) {
        }

        val supportsWidevine = try {
            MediaDrm.isCryptoSchemeSupported(WIDEVINE_UUID)
        } catch (_: Exception) {
            false
        }

        // Dolby support is a decoder fact: ec-3/ac-3/ac-4 present or absent.
        val supportsDolbyAudio = audioCodecs.any {
            it.contains("eac3") || it.contains("ac3") || it.contains("ac4")
        }

        val activityManager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager

        return mapOf(
            "maxSupportedHeight" to maxHeight.takeIf { it > 0 },
            "dynamicRange" to (listOf("sdr") + hdrFormats),
            "videoCodecs" to videoCodecs.toList(),
            "audioCodecs" to audioCodecs.toList(),
            "supportsPip" to context.packageManager.hasSystemFeature(
                PackageManager.FEATURE_PICTURE_IN_PICTURE
            ),
            "supportsHdrPlayback" to supportsHdr,
            "supportsDolbyAudio" to supportsDolbyAudio,
            "supportsWidevine" to supportsWidevine,
            "supportsFairPlay" to false,
            // No DRM is wired up, so offline DRM is false regardless of hardware.
            "supportsOfflineDrm" to false,
            "isLowMemoryDevice" to (activityManager?.isLowRamDevice ?: false),
            "displayHeight" to displayHeight(context)
        )
    }

    private fun currentDisplay(context: Context): Display? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                context.display
            } else {
                @Suppress("DEPRECATION")
                (context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.defaultDisplay
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun displayHeight(context: Context): Int? {
        return try {
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            currentDisplay(context)?.getRealMetrics(metrics)
            maxOf(metrics.widthPixels, metrics.heightPixels).takeIf { it > 0 }
        } catch (_: Exception) {
            null
        }
    }
}
