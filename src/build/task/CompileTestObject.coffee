CompileCoffeeScript = require './CompileCoffeeScript'
path = require('path')


class CompileTestObject extends CompileCoffeeScript

  preCompilerCallback: (coffeeString) ->
    """
currentAbsolutePath = stof.getCurrentAbsolutePath()
currentRelativePath = stof.getCurrentRelativePath()
definePath(__filename)

#{coffeeString}

module.exports = #{path.basename(@params.file, '.coffee')}
stof.setCurrentAbsolutePath(currentAbsolutePath)
stof.setCurrentRelativePath(currentRelativePath)
"""



module.exports = CompileTestObject