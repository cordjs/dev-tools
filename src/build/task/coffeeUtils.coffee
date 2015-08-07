fs   = require 'fs'
path = require 'path'

coffee = require 'coffee-script'

Future = require '../../utils/Future'


exports.compileCoffee = (relativePath, baseDir, targetDir, generateSourceMap, dstName) ->
  ###
  DRY compiles coffee-script file into string with optional source-map included
  @param {string} relativePath - relative to the `baseDir` path of the coffee-file
  @param {string} baseDir - path to the root of the project
  @param {string} targetDir - path to the root of the compiled project
  @param {boolean=} generateSourceMap - if true the result will also include the source-map
  @parma {string=} dstName - name of the destination js file without extension (by default the same as the source file)
  @return {Object} structure with resulting javascript-code string and source-map.
  ###
  dirname = path.dirname(relativePath)
  basename = path.basename(relativePath, '.coffee')

  dstName = basename  if not dstName

  dstDir = "#{targetDir}/#{dirname}"
  dstBasename = "#{dstDir}/#{dstName}"

  src = "#{baseDir}/#{relativePath}"

  Future.call(fs.readFile, src, 'utf8').then (coffeeString) ->
    answer = coffee.compile coffeeString,
      filename: src
      literate: false
      header: true
      compile: true
      bare: true
      sourceMap: generateSourceMap
      jsPath: dstBasename + '.js'
      sourceRoot: './'
      sourceFiles: [path.relative(dstDir, "#{baseDir}/#{dirname}") + "/#{basename}.coffee"]
      generatedFile: dstName + '.js'

    if not generateSourceMap
      js = answer
      answer = {}
      answer.js = js
      answer.v3SourceMap = undefined
    answer.coffeeString = coffeeString
    answer
