fs = require('fs')
path = require('path')

coffee = require('coffee-script')
mkdirp = require('mkdirp')

Future = require('../../utils/Future')

BuildTask = require('./BuildTask')


class CompileCoffeeScript extends BuildTask

  # callback which runs before coffee-script file compilation
  preCompilerCallback: null
  # callback which runs after coffee-script file compilation before writing js output
  postCompilerCallback: null

  run: ->
    dirname = path.dirname(@params.file)
    basename = path.basename(@params.file, '.coffee')

    dstName = if @params.info.isAppConfig then 'application' else basename

    src = "#{ @params.baseDir }/#{ @params.file }"
    dst = "#{ @params.targetDir }/#{ dirname }/#{ dstName }.js"

    Future.call(fs.readFile, src, 'utf8').map (coffeeString) =>
      coffeeString = @preCompilerCallback(coffeeString) if @preCompilerCallback
      js = coffee.compile coffeeString,
        compile: true
        bare: true
      inf = @params.info
      if inf.isWidget or inf.isBehaviour or inf.isModelRepo or inf.isCollection
        name = inf.fileNameWithoutExt
        js = js.replace("return #{name};\n", "#{name}.__name = '#{name}';\n\n   return #{name};\n")
      js = @postCompilerCallback(js) if @postCompilerCallback?
      js
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
