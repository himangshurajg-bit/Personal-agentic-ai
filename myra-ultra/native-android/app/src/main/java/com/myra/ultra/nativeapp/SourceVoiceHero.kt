package com.myra.ultra.nativeapp

import android.animation.ValueAnimator
import android.os.Build
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val SourceInk = Color(0xFF0B0910)
private val SourceCrimson = Color(0xFFFF3B5C)
private val SourceText = Color(0xFFF5F1F8)

/** Native Compose mapping of the source portrait/orb hero; Android session callbacks drive its four states. */
@Composable
internal fun SourceVoiceHero(
    presentation: SourceVoicePresentation,
    compact: Boolean,
    onOrbClick: () -> Unit,
    onSettingsClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val motionEnabled = Build.VERSION.SDK_INT < 26 || ValueAnimator.areAnimatorsEnabled()
    val infinite = rememberInfiniteTransition(label = "myra-source-voice")
    val pulseState = if (motionEnabled && presentation.ringPulses) {
        infinite.animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween(SourceVoiceLayout.pulseDurationMillis, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Restart,
            ),
            label = "voice-pulse",
        )
    } else {
        remember { mutableStateOf(0f) }
    }
    val pulse by pulseState
    val breathState = if (motionEnabled && presentation.breathes) {
        infinite.animateFloat(
            initialValue = 1f,
            targetValue = 0.93f,
            animationSpec = infiniteRepeatable(
                animation = tween(SourceVoiceLayout.breatheDurationMillis),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "thinking-breath",
        )
    } else {
        remember { mutableStateOf(1f) }
    }
    val breath by breathState
    val orbSize = SourceVoiceLayout.orbSizeDp.dp
    val orbScale = (if (compact) SourceVoiceLayout.orbScaleWhenChatting else 1f) *
        (if (motionEnabled && presentation.breathes) breath else 1f)
    val ringColor = Color(presentation.ringColor)
    val orbInteractionSource = remember { MutableInteractionSource() }
    val orbPressed by orbInteractionSource.collectIsPressedAsState()
    val orbPressScale by animateFloatAsState(
        targetValue = sourceOrbScaleWhenPressed(orbPressed),
        animationSpec = tween(SourceVoiceLayout.orbPressTransitionMillis, easing = SourceVoiceLayout.orbPressEasing),
        label = "source-orb-press-scale",
    )
    val orbPixels = with(LocalDensity.current) { orbSize.toPx() }
    val viewportHeight = LocalConfiguration.current.screenHeightDp.toFloat()
    val targetHeight = sourceHeroHeightDp(viewportHeight, compact).dp
    val height by animateDpAsState(
        targetValue = targetHeight,
        animationSpec = if (motionEnabled) {
            tween(
                durationMillis = SourceVoiceLayout.heroHeightTransitionMillis,
                easing = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f),
            )
        } else snap(),
        label = "source-hero-height",
    )
    val portraitPosition by animateFloatAsState(
        targetValue = if (compact) SourceVoiceLayout.sourceImageChattingObjectPositionPercent else SourceVoiceLayout.sourceImageIdleObjectPositionPercent,
        animationSpec = if (motionEnabled) {
            // CSS's default `ease` timing for the 450ms object-position transition.
            tween(
                durationMillis = SourceVoiceLayout.portraitPositionTransitionMillis,
                easing = CubicBezierEasing(0.25f, 0.1f, 0.25f, 1f),
            )
        } else snap(),
        label = "source-portrait-position",
    )

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .background(SourceInk),
    ) {
        Image(
            painter = painterResource(R.drawable.myra_portrait),
            contentDescription = "MYRA portrait",
            contentScale = ContentScale.Crop,
            alignment = sourcePortraitAlignment(portraitPosition),
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            Modifier.fillMaxSize().background(
                Brush.verticalGradient(
                    0f to Color(0x990B0910),
                    0.26f to Color.Transparent,
                    0.52f to Color.Transparent,
                    0.88f to Color(0xE60B0910),
                    1f to SourceInk,
                ),
            ),
        )
        Row(
            Modifier.align(Alignment.TopCenter).fillMaxWidth().padding(horizontal = 14.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("MY", color = SourceText, fontSize = SourceVoiceTypography.brandSizeSp.sp, fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.ExtraBold, letterSpacing = SourceVoiceTypography.brandLetterSpacingSp.sp)
            Text("R", color = SourceCrimson, fontSize = SourceVoiceTypography.brandSizeSp.sp, fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.ExtraBold, letterSpacing = SourceVoiceTypography.brandLetterSpacingSp.sp)
            Text("A", color = SourceText, fontSize = SourceVoiceTypography.brandSizeSp.sp, fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.ExtraBold, letterSpacing = SourceVoiceTypography.brandLetterSpacingSp.sp)
            Spacer(Modifier.weight(1f))
            Surface(color = Color(0x990B0910), shape = CircleShape) {
                TextButtonLabel(onClick = onSettingsClick)
            }
            Spacer(Modifier.width(4.dp))
            IconButton(onClick = onSettingsClick, modifier = Modifier.size(44.dp)) {
                Icon(Icons.Default.Settings, contentDescription = "Settings", tint = SourceText)
            }
        }
        if (!compact) {
            Text(
                "Namaste",
                color = SourceText,
                fontSize = SourceVoiceTypography.greetingSizeSp.sp,
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.ExtraBold,
                modifier = Modifier.align(Alignment.BottomStart).padding(start = 18.dp, bottom = 124.dp),
            )
        }
        Column(
            modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = SourceVoiceLayout.dockBottomDp.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                Modifier.size(orbSize + 16.dp).scale(orbScale),
                contentAlignment = Alignment.Center,
            ) {
                if (motionEnabled && presentation.ringPulses) {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .scale(0.9f + pulse * 0.45f)
                            .border(2.dp, ringColor.copy(alpha = 0.85f * (1f - pulse)), CircleShape),
                    )
                }
                Surface(
                    onClick = onOrbClick,
                    shape = CircleShape,
                    color = Color.Transparent,
                    shadowElevation = 12.dp,
                    interactionSource = orbInteractionSource,
                    modifier = Modifier.size(orbSize).scale(orbPressScale).semantics {
                        contentDescription = if (presentation.state == SourceVoiceState.IDLE) {
                            "Live baat-cheet shuru karo"
                        } else {
                            "Live band karo"
                        }
                    },
                ) {
                    Box(
                        Modifier
                            .fillMaxSize()
                            .border(2.dp, ringColor, CircleShape)
                            .background(
                                Brush.radialGradient(
                                    colorStops = arrayOf(
                                        0f to when (presentation.state) {
                                            SourceVoiceState.LISTENING -> Color(0xFF9CF5CD)
                                            SourceVoiceState.THINKING -> Color(0xFFFFC29B)
                                            SourceVoiceState.SPEAKING -> Color(0xFFB8ECFF)
                                            SourceVoiceState.IDLE -> Color(0xFFFF8AA0)
                                        },
                                        (if (presentation.state == SourceVoiceState.IDLE) 0.40f else 0.42f) to ringColor,
                                        (if (presentation.state == SourceVoiceState.IDLE) SourceVoiceLayout.idleGradientEndStop else SourceVoiceLayout.activeGradientEndStop) to when (presentation.state) {
                                            SourceVoiceState.LISTENING -> Color(0xFF16845A)
                                            SourceVoiceState.THINKING -> Color(0xFFB4501B)
                                            SourceVoiceState.SPEAKING -> Color(0xFF1E7EA0)
                                            SourceVoiceState.IDLE -> Color(0xFFC81F3F)
                                        },
                                    ),
                                    center = Offset(orbPixels * SourceVoiceLayout.gradientCenterX, orbPixels * SourceVoiceLayout.gradientCenterY),
                                    radius = orbPixels * SourceVoiceLayout.gradientRadius,
                                ),
                                CircleShape,
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        SourceMicGlyph(
                            strokeWidth = if (presentation.state == SourceVoiceState.IDLE) SourceVoiceLayout.idleMicStroke else SourceVoiceLayout.liveMicStroke,
                            modifier = Modifier.fillMaxSize(0.36f),
                        )
                    }
                }
            }
            Spacer(Modifier.height(SourceVoiceLayout.dockGapDp.dp))
            Text(
                presentation.status,
                color = SourceText,
                fontSize = SourceVoiceTypography.statusSizeSp.sp,
                fontFamily = FontFamily.SansSerif,
                modifier = Modifier.padding(horizontal = 12.dp).semantics {
                    liveRegion = LiveRegionMode.Polite
                },
            )
        }
    }
}

@Composable
private fun SourceMicGlyph(strokeWidth: Float, modifier: Modifier = Modifier) {
    androidx.compose.foundation.Canvas(modifier) {
        val sx = size.width / 24f
        val sy = size.height / 24f
        val path = Path().apply {
            moveTo(5f * sx, 11f * sy)
            cubicTo(5f * sx, 14.866f * sy, 8.134f * sx, 18f * sy, 12f * sx, 18f * sy)
            cubicTo(15.866f * sx, 18f * sy, 19f * sx, 14.866f * sy, 19f * sx, 11f * sy)
            moveTo(12f * sx, 18f * sy)
            lineTo(12f * sx, 21f * sy)
        }
        drawRoundRect(
            color = Color.White,
            topLeft = Offset(9f * sx, 3f * sy),
            size = Size(6f * sx, 12f * sy),
            cornerRadius = CornerRadius(3f * sx, 3f * sy),
            style = Stroke(width = strokeWidth * sx, cap = StrokeCap.Round, join = StrokeJoin.Round),
        )
        drawPath(
            path = path,
            color = Color.White,
            style = Stroke(width = strokeWidth * sx, cap = StrokeCap.Round, join = StrokeJoin.Round),
        )
    }
}

@Composable
private fun TextButtonLabel(onClick: () -> Unit) {
    androidx.compose.material3.TextButton(onClick = onClick, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp)) {
        Text("Auto", color = SourceText, fontSize = SourceVoiceTypography.chipSizeSp.sp, fontFamily = FontFamily.SansSerif)
    }
}

/** Compose equivalent of CSS object-position:50% y% after object-fit:cover. */
internal fun sourcePortraitAlignment(objectPositionYPercent: Float): Alignment = Alignment { content, container, _ ->
    IntOffset(
        sourceObjectPositionOffset(container.width, content.width, 50f),
        sourceObjectPositionOffset(container.height, content.height, objectPositionYPercent),
    )
}
