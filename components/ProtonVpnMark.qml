// The Proton VPN mark, drawn from its single-path SVG glyph.
//
// Single path, no baked gradient, so `markColor` fully controls it and the mark
// follows the DMS theme. The source glyph is monochrome (#66DEB1); that fill is
// discarded here — all state lives in the color the caller passes in.

import QtQuick
import QtQuick.Shapes
import qs.Common

Item {
    id: logo

    property real size: 24
    property color markColor: Theme.surfaceText

    // Breathes while a connect or disconnect is in flight, since the color only
    // changes once the tunnel does. Animates the Shape rather than the Item so
    // it composes with whatever opacity the caller binds.
    property bool pulsing: false

    // Source viewBox. The path is authored in these units and scaled to `size`.
    readonly property real viewBox: 24

    width: size
    height: size

    SequentialAnimation {
        running: logo.pulsing
        loops: Animation.Infinite
        // Settle back to full strength rather than freezing mid-fade.
        onStopped: glyph.opacity = 1

        NumberAnimation {
            target: glyph
            property: "opacity"
            to: 0.35
            duration: 600
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            target: glyph
            property: "opacity"
            to: 1
            duration: 600
            easing.type: Easing.InOutSine
        }
    }

    Shape {
        id: glyph
        width: logo.viewBox
        height: logo.viewBox
        preferredRendererType: Shape.CurveRenderer

        // Scale origin defaults to (0,0), so the scaled mark fills the Item
        // from the top-left. Do not anchor-center the Shape as well.
        transform: Scale {
            xScale: logo.size / logo.viewBox
            yScale: logo.size / logo.viewBox
        }

        ShapePath {
            fillColor: logo.markColor
            strokeWidth: 0
            fillRule: ShapePath.WindingFill

            PathSvg {
                path: "m10.176 20.058.858-1.28 6.513-9.838c.57-.86.026-2.014-1.005-2.131L.378 4.95l8.373 15.055a.84.84 0 0 0 1.424.052h.001zM23.586 7.14l-9.662 14.61c-1.036 1.567-3.38 1.478-4.293-.162l-.093-.168c.3-.01.594-.086.855-.235a1.85 1.85 0 0 0 .612-.57l.86-1.28 6.516-9.844c.46-.694.525-1.56.173-2.314a2.375 2.375 0 0 0-1.899-1.364L.493 3.956l-.476-.054C-.163 2.392 1.101.95 2.784 1.143l18.991 2.16c1.856.21 2.835 2.289 1.812 3.838z"
            }

            Behavior on fillColor {
                ColorAnimation {
                    duration: Theme.shortDuration
                }
            }
        }
    }
}
