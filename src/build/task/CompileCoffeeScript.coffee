fs = require 'fs'
path = require 'path'

mkdirp = require 'mkdirp'

Future = require '../../utils/Future'

BuildTask = require './BuildTask'
coffeeUtils = require './coffeeUtils'


class CompileCoffeeScript extends BuildTask

  run: ->
    dirname = path.dirname(@params.file)
    basename = path.basename(@params.file, '.coffee')

    dstName = if @params.info.isAppConfig then 'application' else basename

    src = "#{ @params.baseDir }/#{ @params.file }"
    dstDir = "#{ @params.targetDir }/#{ dirname }"
    dstBasename = "#{ dstDir}/#{ dstName }"

    compilePromise = coffeeUtils.compileCoffee(
      @params.file, @params.baseDir, @params.targetDir, @params.generateSourceMap, dstName
    ).then (answer) =>
      inf = @params.info
      if inf.isWidget or inf.isBehaviour or inf.isModelRepo or inf.isCollection
        name = inf.fileNameWithoutExt
        replacement = "#{name}.__name = '#{name}';\n";
        if inf.isWidget
          templatePath = "#{@params.baseDir}/#{dirname}/#{inf.lastDirName}.html"
          hasOwnTemplate = if fs.existsSync(templatePath)
            'true'
          else
            'false'
          replacement += "#{name}.__hasOwnTemplate = #{hasOwnTemplate};\n"
        replacement += "return #{name};\n"
        answer.js = answer.js.replace("return #{name};\n", replacement)
      if @params.generateSourceMap
        answer.js = "#{answer.js}\n//# sourceMappingURL=#{dstName}.map"
      answer

    Future.all [
      compilePromise
      Future.call(mkdirp, path.dirname(dstBasename))
    ]
    .spread (answer) ->
      Future.all [
        Future.call(fs.writeFile, "#{dstBasename}.js", answer.js)
        if undefined != answer.v3SourceMap
          Future.call(fs.writeFile, "#{dstBasename}.map", answer.v3SourceMap)
        else
          undefined
      ]
    .catch (err) ->
      if err instanceof SyntaxError and err.location?
        console.error "CoffeeScript syntax error: #{err.message}\n" +
          "#{src}:#{err.location.first_line}:#{err.location.first_column}\n"
        throw new BuildTask.ExpectedError(err)
      else
        throw err
    .then -> return
    .link(@readyPromise)



module.exports = CompileCoffeeScript
