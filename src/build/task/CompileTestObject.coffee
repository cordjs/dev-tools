CompileCoffeeScript = require './CompileCoffeeScript'
path = require('path')


class CompileTestObject extends CompileCoffeeScript

  preCompilerCallback: (coffeeString) ->
    coffeeString + "\nmodule.exports = " + path.basename(@params.file, '.coffee')



module.exports = CompileTestObject