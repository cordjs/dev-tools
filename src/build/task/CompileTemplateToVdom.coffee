fs     = require 'fs'
path   = require 'path'
mkdirp = require 'mkdirp'

Future = require '../../utils/Future'

BuildTask = require './BuildTask'

dustVdom = require './dust-vdom'

class CompileTemplateToVdom extends BuildTask

  run: ->
    dirname = path.dirname(@params.file)
    basename = path.basename(@params.file, '.html')

    src = "#{ @params.baseDir }/#{ @params.file }"
    dst = "#{ @params.targetDir }/#{ dirname }/#{ basename }.js"

    Future.call(fs.readFile, src, 'utf8').then (dustString) =>
      parsed = dustVdom.parse(dustString)
      vdomString = JSON.stringify(parsed, null, 2)
      console.log "----------------VDOM-------------------------"
      console.log vdomString
      console.log "---------------------------------------------"
      vdomString
    .zip(Future.call(mkdirp, path.dirname(dst))).then (vdomString) =>
      Future.call(fs.writeFile, dst, vdomString)
    .link(@readyPromise)
    .failAloud()



module.exports = CompileTemplateToVdom
