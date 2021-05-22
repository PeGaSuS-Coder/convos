const postcss = require('rollup-plugin-postcss');

module.exports = function(config) {
  config.plugins.push(postcss({
    extract: true,
    plugins: [
      require('@csstools/postcss-sass')(),
      require('postcss-preset-env')(),
      require('cssnano'),
    ],
  }));
};
