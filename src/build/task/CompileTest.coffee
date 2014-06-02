fs = require('fs')
path = require('path')

coffee = require('coffee-script')
mkdirp = require('mkdirp')

Future = require('../../utils/Future')

CompileCoffeeScript = require('./CompileCoffeeScript')


class CompileTest extends CompileCoffeeScript

  postCompilerCallback: (jsString) ->
    jsString = "definePath(__filename, __dirname);" + jsString

    jsString



module.exports = CompileTest
