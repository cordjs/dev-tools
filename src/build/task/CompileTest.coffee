CompileCoffeeScript = require('./CompileCoffeeScript')


class CompileTest extends CompileCoffeeScript

  postCompilerCallback: (jsString) ->
    "definePath(__filename, __dirname);" + jsString



module.exports = CompileTest
