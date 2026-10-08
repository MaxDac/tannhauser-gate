// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/tannhauser_gate_web.ex",
    "../lib/tannhauser_gate_web/**/*.*ex"
  ],
  theme: {
    extend: {
      // Console green palette. The primary is a softened phosphor green rather
      // than pure #00ff00 to limit glare; body copy uses green-tinted greys.
      // Contrast on `night`: phosphor 11.3:1, mint 12.2:1, fog-200 13.1:1,
      // fog-400 7.3:1, fog-500 5.1:1 (WCAG AA). `phosphor-dim` is for borders only.
      colors: {
        brand: "#4ae08a",
        phosphor: {DEFAULT: "#4ae08a", bright: "#9bf5bf", dim: "#2c8f58"},
        mint: "#86e0b0",
        night: "#0b100d",
        ink: "#121a15",
        fog: {
          100: "#e2ece5",
          200: "#cad9cf",
          300: "#aec2b5",
          400: "#8ea596",
          500: "#72897a",
          600: "#556a5c",
          700: "#3c4d42",
          800: "#26322a",
          900: "#18211b",
        },
      },
      fontFamily: {
        display: ["Orbitron", "Rajdhani", "Eurostile", "ui-sans-serif", "system-ui", "sans-serif"],
        hand: ["\"Special Elite\"", "\"Courier Prime\"", "\"Courier New\"", "ui-monospace", "monospace"],
      },
      boxShadow: {
        phosphor: "0 0 0 1px rgba(74,224,138,0.22), 0 0 20px rgba(74,224,138,0.12)",
      }
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function({matchComponents, theme}) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
        })
      })
      matchComponents({
        "hero": ({name, fullPath}) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          let size = theme("spacing.6")
          if (name.endsWith("-mini")) {
            size = theme("spacing.5")
          } else if (name.endsWith("-micro")) {
            size = theme("spacing.4")
          }
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--hero-${name})`,
            "mask": `var(--hero-${name})`,
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            "width": size,
            "height": size
          }
        }
      }, {values})
    })
  ]
}
