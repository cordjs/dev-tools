fs     = require 'fs'
path   = require 'path'
mkdirp = require 'mkdirp'
_      = require 'underscore'

Future = require '../../utils/Future'

BuildTask = require './BuildTask'

dustVdom = require './dust-vdom'


class CompileTemplateToVdom extends BuildTask

  run: ->
    dirname = path.dirname(@params.file)
    basename = path.basename(@params.file, '.html')

    src = "#{ @params.baseDir }/#{ @params.file }"
    dst = "#{ @params.targetDir }/#{ dirname }/#{ basename }.js"

    compilePromise = Future.call(fs.readFile, src, 'utf8').then (dustString) =>
      ast = dustVdom.parse(dustString)
      console.log "----------------VDOM-------------------------"
      console.log JSON.stringify(ast, null, 2)
      console.log "---------------------------------------------"
      if ast.length > 1
        console.warn "Only single root node is allowed for the widget! Using only first of #{ast.length}! [#{src}]"
        ast = [ast[0]]
      hyperscript = astToHyperscript(ast, 1)
      console.log hyperscript
      console.log "---------------------------------------------"
      """
      define(['cord!vdom/vhyperscript/h'],function(h){
        var w = h.w;
        return function(props, state, calc){ return #{hyperscript}; };
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



astToHyperscript = (ast, indent = 0) ->
  indentPrefix = (new Array(indent * 2 + 1)).join(' ')
  prevIndentPrefix = if indent > 0 then (new Array((indent - 1) * 2 + 1)).join(' ') else ''
  childIndent = if ast.length > 1 then "\n#{indentPrefix}" else ''
  chunks =
    for node in ast
      switch node.type
        when 'html_tag'
          if node.name == 'widget'
            compileWidget(node, indent)
          else
            contentsStr = ''
            contentsStr = astToHyperscript(node.contents, indent + 1) if node.contents
            contentsStr = ', ' + contentsStr if contentsStr

            propsStr = propsToHyperscript(node.props, indent)

            idStr = if indent == 0 then "+'#'+props.id" else ''
            "h('#{node.name}'#{idStr}#{propsStr}#{contentsStr})"

        when 'text'
          "'#{node.text}'"

        when 'expr'
          "String(#{node.code})"

  chunks = mergeTextChunks(chunks, ast)

  if chunks.length > 1
    "[#{childIndent}#{chunks.join(',' + childIndent)}\n#{prevIndentPrefix}]"
  else if chunks.length == 1
    chunks[0]
  else
    ''

compileWidget = (node, indent = 0) ->
  contentsStr = ''
  contentsStr = astToHyperscript(node.contents, indent + 1) if node.contents
  contentsStr = ', ' + contentsStr if contentsStr

  for prop, i in node.props
    if prop.name == 'type'
      type = compilePropValue(prop.value)
      node.props.splice(i, 1)
      break

  propsStr = propsToHyperscript(node.props, indent)

  "w(#{type}#{propsStr}#{contentsStr})"


compilePropValue = (propValue) ->
  if _.isString(propValue)
    "'#{propValue}'"
  else if _.isObject(propValue)
    switch propValue.type
      when 'expr' then propValue.code
      else
        throw new Error("Invalid prop value type '#{propValue.type}'!")
  else
    throw new Error("Invalid prop value type parsed: #{propValue}!")


mergeTextChunks = (chunks, ast) ->
  result = []
  prevVtext = false
  for node, i in ast
    curVtext = node.type in ['text', 'expr']
    if curVtext and prevVtext
      result[result.length - 1] += ' + ' + chunks[i]
    else
      result.push(chunks[i])
    prevVtext = curVtext
  result


propsToHyperscript = (props, indent = 0) ->
  return '' if not props or props.length == 0
  chunks =
    for propInfo in props
      value = compilePropValue(propInfo.value)
      "#{propInfo.name}: #{value}"

  pairs =
    if chunks.length > 1
      indentStr = "\n" + (new Array((indent + 1) * 2 + 1)).join(' ')
      prevIndentPrefix = (new Array(indent * 2 + 1)).join(' ')
      "#{indentStr}#{chunks.join(',' + indentStr)}\n#{prevIndentPrefix}"
    else
      " #{chunks[0]} "
  ", {#{pairs}}"



module.exports = CompileTemplateToVdom
