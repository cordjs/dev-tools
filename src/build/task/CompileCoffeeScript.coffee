fs = require('fs')
path = require('path')
coffee = require('coffee-script')
mkdirp = require('mkdirp')
Future = require('../../utils/Future')
BuildTask = require('./BuildTask')


class CompileCoffeeScript extends BuildTask

  run: ->
    dirname = path.dirname(@params.file)
    basename = path.basename(@params.file, '.coffee')

    src = "#{ @params.baseDir }/#{ @params.file }"
    dst = "#{ @params.targetDir }/#{ dirname }/#{ basename }.js"

    Future.call(fs.readFile, src, 'utf8').map (coffeeString) ->
      coffee.compile coffeeString,
        compile: true
        bare: true
    .zip(Future.call(mkdirp, path.dirname(dst))).flatMap (jsString) =>
      Future.call(fs.writeFile, dst, jsString)
    .flatMapFail (err) ->
      if err instanceof SyntaxError and err.location?
        console.error "CoffeeScript syntax error: #{err.message}\n" +
          "#{src}:#{err.location.first_line}:#{err.location.first_column}\n"
        Future.rejected(new BuildTask.ExpectedError(err))
      else
        Future.rejected(err)
    .link(@readyPromise)



module.exports = CompileCoffeeScript
