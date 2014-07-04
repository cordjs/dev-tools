CompileCoffeeScript = require './CompileCoffeeScript'
coffee = require 'coffee-script'

definePathString = "definePath(__filename)\n"
setUncaughtExceptionHandlerString = "setUncaughtExceptionHandler(__filename)\n"

class CompileTestSpec extends CompileCoffeeScript

  preCompilerCallback: (coffeeString) ->
    # Parse source coffee script string
    tokens = coffee.tokens(coffeeString)

    inIt = false
    linesToPaste = []

    # find it-calls and stores their position and indent
    for key, token of tokens
      if not inIt and token[0] == 'IDENTIFIER' and token[1] == 'it'
        inIt = true
      else if inIt and token[0] == 'INDENT'
        inIt = false
        linesToPaste.push( line: token[2].first_line, indent: token[2].last_column + 1 )

    linesToPaste = linesToPaste.reverse()

    # insert after it-calls definePath-call
    for key, elem of linesToPaste
      {line, indent} = elem
      lineStartPos = @_lineStartPos(coffeeString, line)
      coffeeString = coffeeString.substr(0, lineStartPos) + "\n" + @_pad('', indent) + definePathString + coffeeString.substr(lineStartPos)

    definePathString + setUncaughtExceptionHandlerString + coffeeString


  _pad: (str, width) ->
    len = Math.max(0, width - str.length)
    str + Array(len + 1).join(' ')


  _lineStartPos: (string, line) ->
    lineStartPos = 0
    i = 0
    while i < line
      lineStartPos = string.indexOf("\n", lineStartPos) + 1
      i++
    lineStartPos



module.exports = CompileTestSpec
