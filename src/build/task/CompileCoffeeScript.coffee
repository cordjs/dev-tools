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
    dstBasename = "#{ @params.targetDir }/#{ dirname }/#{ dstName }"

    Future.call(fs.readFile, src, 'utf8').map (coffeeString) =>
      coffeeString = @preCompilerCallback(coffeeString) if @preCompilerCallback
      answer = coffee.compile coffeeString,
        filename: src
        literate: false
        header: true
        compile: true
        bare: true
        sourceMap: @params.generateSourceMap
        jsPath: "#{ dstBasename }.js"
        sourceRoot: './'
        sourceFiles: [dstName+'.coffee']
        generatedFile: dstName+'.js'

      if not @params.generateSourceMap
        js = answer
        answer = {}
        answer.js = js
        answer.v3SourceMap = undefined
      answer.coffeeString = coffeeString
      inf = @params.info
      if inf.isWidget or inf.isBehaviour or inf.isModelRepo or inf.isCollection
        name = inf.fileNameWithoutExt
        answer.js = answer.js.replace("return #{name};\n", "#{name}.__name = '#{name}';\n\n   return #{name};\n")
      answer.js = @postCompilerCallback(answer.js) if @postCompilerCallback?
      if @params.generateSourceMap
        answer.js = "#{answer.js}\n//# sourceMappingURL=./#{dstName}.js.map"
      answer
    .zip(Future.call(mkdirp, path.dirname(dstBasename))).flatMap (answer) =>
      Future.sequence([
        Future.call(fs.writeFile, "#{dstBasename}.js", answer.js)
        if undefined != answer.v3SourceMap
          Future.call(fs.writeFile, "#{dstBasename}.js.map", answer.v3SourceMap)
        else
          Future.resolved()
        # If we are also generating source maps, we should copy link coffee file to public directory
        if undefined != answer.v3SourceMap
          Future.call(fs.symlink, src, "#{dstBasename}.coffee").catch () -> undefined # ignore already exists symlink
        else
          Future.resolved()
      ])
    .flatMapFail (err) ->
      if err instanceof SyntaxError and err.location?
        console.error "CoffeeScript syntax error: #{err.message}\n" +
          "#{src}:#{err.location.first_line}:#{err.location.first_column}\n"
        Future.rejected(new BuildTask.ExpectedError(err))
      else
        Future.rejected(err)
    .link(@readyPromise)



module.exports = CompileCoffeeScript
