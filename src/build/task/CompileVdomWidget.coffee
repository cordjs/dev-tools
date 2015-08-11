fs     = require 'fs'
path   = require 'path'
mkdirp = require 'mkdirp'

stylus = require 'stylus'
poststylus = require 'poststylus'
cssSelectorParser = require 'postcss-selector-parser'

fsUtils = require '../../utils/fsUtils'
Future = require '../../utils/Future'

BuildTask = require './BuildTask'
coffeeUtils = require './coffeeUtils'
stylusUtils = require './stylusUtils'

dustVdomCompiler = require './dustVdomCompiler'


class CompileVdomWidget extends BuildTask

  run: ->
    dirname = path.dirname(@params.file)
    basename = path.basename(@params.file, '.coffee')

    dstDir = "#{ @params.targetDir }/#{ dirname }"
    dstBasename = "#{dstDir}/#{basename}"

    compilePromise = Future.all [
      coffeeUtils.compileCoffee(@params.file, @params.baseDir, @params.targetDir, @params.generateSourceMap)
      @_getCompiledVdomTemplate()
      @_getCssInfo()
    ]
    .spread (jsResult, vdomTemplateResult, cssInfoJson) ->
      name = basename
      replacement = "#{name}.__name = '#{name}';\n\n";

      replacement += """
      // --- begin compiled vdom template ---
          var h = #{name}.h, w = h.w, v = h.v;
          #{vdomTemplateResult.blockFns.join("\n    ")}
          #{name}.__render = function __render(props, state, calc) {
            return #{vdomTemplateResult.hyperscript};
          };
      // --- end compiled vdom template ---

          #{name}.__cssInfo = #{cssInfoJson};

          return #{name};\n
      """

      jsResult.js = jsResult.js.replace("return #{name};\n", replacement)
      jsResult

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
    .failAloud('CompileVdomWidget::run')


  _getCompiledVdomTemplate: ->
    ###
    Compiles vdom-template or returns cached template compilation result.
    @return {Object} structure with array of block functions (string) and root hyperscript (string)
    ###
    dirname = path.dirname(@params.file)
    basename = path.basename(dirname) + '.vdom'

    info = @params.info
    file = "#{dirname}/#{basename}.html"

    src = "#{ @params.baseDir }/#{file}"
    dst = "#{ @params.targetDir }/#{dirname}/#{basename}.json"

    if info.templateModified
      compileAndCacheVdomTemplate(src, dst)
    else
      fsUtils.exists(dst).then (exists) ->
        if exists
          Future.call(fs.readFile, dst).then (jsonString) ->
            JSON.parse(jsonString)
        else
          compileAndCacheVdomTemplate(src, dst)



  _getCssInfo: ->
    ###
    Compiles vdom-widget's stylus-file to css and returns resulting or cached css-class mappings.
    @return {Object} css-class map
    ###
    info = @params.info
    return '{}'  if not info.stylusExists

    dirname = path.dirname(@params.file)
    basename = path.basename(dirname)

    file = "#{dirname}/#{basename}"

    cssInfoFile = "#{ @params.targetDir }/#{dirname}/cssInfo.json"

    if info.stylusModified
      compileAndCacheStylus(file, @params)
    else
      fsUtils.exists(cssInfoFile).then (exists) =>
        if exists
          Future.call(fs.readFile, cssInfoFile)
        else
          compileAndCacheStylus(file, @params)



compileAndCacheVdomTemplate = (src, dst) ->
  ###

  ###
  Future.all [
    dustVdomCompiler.compile(src, 3)
    Future.call(mkdirp, path.dirname(dst))
  ]
  .spread (vdomJsInfo) ->
    Future.call(fs.writeFile, dst, JSON.stringify(vdomJsInfo, null, 2)).then ->
      vdomJsInfo


compileAndCacheStylus = (srcWithoutExt, params) ->
  ###
  Compiles the given stylus file with preprocessing of @include and @require directives.
  @param {string} srcWithoutExt - path to the source stylus file without extension and relative to the project root
  @param {Object} params - build params need to know project root(base) directory and target directory
  @return {Promise.<string>} stringified JSON with CSS info (class map and required css-files)
                             to be injected to the widget class
  ###
  basename = path.basename(srcWithoutExt)
  widgetName = basename.charAt(0).toUpperCase() + basename.slice(1)
  src = "#{params.baseDir}/#{srcWithoutExt}.styl"
  dst = "#{params.targetDir}/#{srcWithoutExt}.css"
  dstDir = path.dirname(dst)

  cssClassMap = {}
  cssDeps = null

  compilePromise = Future.call(fs.readFile, src, 'utf8').then (stylusStr) =>
    stylusUtils.preprocessWidgetStylus(stylusStr, srcWithoutExt, params.targetDir)
  .spread (preprocessedStr, deps) ->
    cssDeps = deps
    styl = stylus(preprocessedStr)
      .set('filename', src)
      .set('compress', true)
      .include(params.targetDir)
      .use(stylusUtils.importStylusLibs)
      .use(poststylus(prependWidgetPrefix(widgetName, cssClassMap)))
    Future.call([styl, 'render'])
  .catch (err) ->
    if err.constructor.name == 'ParseError'
      console.error "Stylus ParseError:\n#{err.message}"
      throw new BuildTask.ExpectedError(err)
    else
      throw err

  Future.all [
    compilePromise
    Future.call(mkdirp, dstDir)
  ]
  .spread (cssStr) ->
    hasMeaningfulCss = cssStr.trim() != ''
    if hasMeaningfulCss
      cssDeps.push(srcWithoutExt.slice(6)) # cutting "public" prefix
    cssInfoString = JSON.stringify(classMap: cssClassMap, deps: cssDeps)
    Future.all [
      hasMeaningfulCss and Future.call(fs.writeFile, dst, cssStr)
      Future.call(fs.writeFile, "#{dstDir}/cssInfo.json", cssInfoString)
    ]
    .then ->
      cssInfoString


prependWidgetPrefix = (widgetName, cssClassMap) ->
  ###
  Creates and returns PostCSS plugin function that prefixes all classnames in the applied css with the given widgetName
  @param {string} widgetName - the prefix
  @param {Object} cssClassMap - injected object that is filled by the plugin with the map of the replaced classes
  @return {function}
  ###
  selectorParser = cssSelectorParser (selectors) ->
    selectors.eachClass (selector) ->
      prefixedClass = widgetName + '__' + selector.value
      cssClassMap[selector.value] = prefixedClass
      selector.value = prefixedClass
      return

  (css) ->
    css.eachRule (rule) ->
      rule.selectors = rule.selectors.map (selector) ->
        selectorParser.process(selector).result
      return



module.exports = CompileVdomWidget
