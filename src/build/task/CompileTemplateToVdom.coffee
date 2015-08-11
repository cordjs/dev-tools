fs     = require 'fs'
path   = require 'path'
mkdirp = require 'mkdirp'
_      = require 'underscore'

Future = require '../../utils/Future'

BuildTask = require './BuildTask'

dustVdomCompiler = require './dustVdomCompiler'


class CompileTemplateToVdom extends BuildTask

  run: ->
    dirname = path.dirname(@params.file)
    basename = path.basename(@params.file, '.html')

    src = "#{ @params.baseDir }/#{ @params.file }"
    dst = "#{ @params.targetDir }/#{ dirname }/#{ basename }.js"

    dustVdomCompiler.compile(src).then (info) ->
      console.log info.hyperscript
      console.log "---------------------------------------------"
      """
      define(['cord!vdom/vhyperscript/h'],function(h){
        var w = h.w, v = h.v;
        #{info.blockFns.join("\n  ")}
        return function(props, state, calc){ return #{info.hyperscript}; };
      });
      """

    Future.all [
      compilePromise
      Future.call(mkdirp, path.dirname(dst))
    ]
    .spread (vdomJs) =>
      Future.call(fs.writeFile, dst, vdomJs)
    .link(@readyPromise)
    .failAloud('CompileTemplateToVdom::run')



module.exports = CompileTemplateToVdom
