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
      ast = dustVdom.parse(dustString)
      hyperscript = astToHyperscript(ast)
      console.log "----------------VDOM-------------------------"
      console.log JSON.stringify(ast, null, 2)
      console.log "---------------------------------------------"
      console.log hyperscript
      console.log "---------------------------------------------"
      "define(function(){ return #{hyperscript};});"
    .zip(Future.call(mkdirp, path.dirname(dst))).then (vdomJs) =>
      Future.call(fs.writeFile, dst, vdomJs)
    .link(@readyPromise)
    .failAloud()



astToHyperscript = (ast, indent = 1) ->
  indentPrefix = (new Array(indent * 2 + 1)).join(' ')
  prevIndentPrefix = (new Array((indent - 1) * 2 + 1)).join(' ')
  chunks =
    for node in ast
      switch node.type
        when 'html_tag'
          contentsStr = ''
          contentsStr = astToHyperscript(node.contents, indent + 1) if node.contents
          contentsStr = ', ' + contentsStr if contentsStr
          "\n#{indentPrefix}h('#{node.name}'#{contentsStr})"
  result = ''
  result = '[' + chunks.join(',') + "\n" + prevIndentPrefix + ']' if ast.length
  result


module.exports = CompileTemplateToVdom
