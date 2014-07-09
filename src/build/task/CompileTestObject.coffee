CompileCoffeeScript = require './CompileCoffeeScript'
path = require('path')


class CompileTestObject extends CompileCoffeeScript

  preCompilerCallback: (coffeeString) ->
    """
context = stof.getCurrentContext()
stof.defineContext(__filename, false)

#{coffeeString}

module.exports = #{path.basename(@params.file, '.coffee')}

stof.defineContext(context, false)
"""



module.exports = CompileTestObject