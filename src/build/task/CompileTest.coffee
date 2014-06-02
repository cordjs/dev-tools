CompileCoffeeScript = require './CompileCoffeeScript'


class CompileTest extends CompileCoffeeScript

  postCompilerCallback: (jsString) ->
    "definePath(__filename, __dirname);\n" + jsString



module.exports = CompileTest
