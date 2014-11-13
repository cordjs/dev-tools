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
      console.log "----------------VDOM-------------------------"
      console.log JSON.stringify(ast, null, 2)
      console.log "---------------------------------------------"
      if ast.length > 1
        console.warn "Only single root node is allowed for the widget! Using only first of #{ast.length}! [#{src}]"
        ast = [ast[0]]
      hyperscript = astToHyperscript(ast)
      console.log hyperscript
      console.log "---------------------------------------------"
      "define(['cord!vdom/vhyperscript/h'],function(h){ return function(props, state, calc){ return #{hyperscript};};});"
    .zip(Future.call(mkdirp, path.dirname(dst))).then (vdomJs) =>
      Future.call(fs.writeFile, dst, vdomJs)
    .link(@readyPromise)
    .failAloud()



astToHyperscript = (ast, indent = 0) ->
  indentPrefix = (new Array(indent * 2 + 1)).join(' ')
  prevIndentPrefix = if indent > 0 then (new Array((indent - 1) * 2 + 1)).join(' ') else ''
  chunks =
    for node in ast
      switch node.type
        when 'html_tag'
          contentsStr = ''
          contentsStr = astToHyperscript(node.contents, indent + 1) if node.contents
          contentsStr = ', ' + contentsStr if contentsStr
          idStr = if indent == 0 then "+'#'+props.id" else ''
          indentStr = if indent == 0 then '' else "\n#{indentPrefix}"
          "#{indentStr}h('#{node.name}'#{idStr}#{contentsStr})"

        when 'text'
          "\n#{indentPrefix}'#{node.text}'"

        when 'expr'
          "\n#{indentPrefix}String(#{node.code})"

  if ast.length > 1
    '[' + chunks.join(',') + "\n" + prevIndentPrefix + ']'
  else if ast.length == 1
    chunks[0]
  else
    ''


module.exports = CompileTemplateToVdom
