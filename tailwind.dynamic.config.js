const path = require('path')

module.exports = {
  future: {
    hoverOnlyWhenSupported: true
  },
  content: [
    path.resolve(__dirname, 'app/javascript/template_builder/dynamic_area.vue'),
    path.resolve(__dirname, 'app/javascript/template_builder/dynamic_section.vue')
  ],
  theme: {
    extend: {
      colors: {
        'base-100': '#ffffff',
        'base-200': '#fbf8f2',
        'base-300': '#e6e0d3',
        'base-content': '#111111'
      }
    }
  }
}
