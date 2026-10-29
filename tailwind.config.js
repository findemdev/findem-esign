// Findem Studio's app brand: ink and warm neutrals, Season type, 8px controls and 14px cards.
module.exports = {
  future: {
    hoverOnlyWhenSupported: true
  },
  theme: {
    extend: {
      fontFamily: {
        sans: ['"Season Sans"', 'Inter', '"Helvetica Neue"', 'Arial', 'sans-serif'],
        serif: ['"Season Serif"', 'Georgia', 'serif']
      }
    }
  },
  plugins: [
    require('daisyui')
  ],
  daisyui: {
    themes: [
      {
        docuseal: {
          'color-scheme': 'light',
          primary: '#efebe2',
          secondary: '#f6ebb0',
          accent: '#e9cf3b',
          neutral: '#111111',
          'neutral-focus': '#262522',
          'base-100': '#ffffff',
          'base-200': '#fbf8f2',
          'base-300': '#e6e0d3',
          'base-content': '#111111',
          '--rounded-box': '0.875rem',
          '--rounded-btn': '0.5rem',
          '--btn-text-case': 'none',
          '--tab-border': '2px',
          '--tab-radius': '.5rem'
        }
      }
    ]
  }
}
