should = require 'should'
CompileTestSpec = require '../task/CompileTestSpec'

describe 'Test compiler check', ->
  compileTest = new CompileTestSpec
  defineContextString = "stof.defineContext(__filename, false)"
  defineContextStringInItBlock = "stof.defineContext(__filename)"

  it 'Checks simple case, which consists of it with describe message without done argument', ->
    coffeeScript = """
describe 'One test, one touch', ->
  it 'should test something', ->
    nextCall()
"""
    compileTest.preCompilerCallback(coffeeScript).should.equal """
#{defineContextString}
describe 'One test, one touch', ->
  it 'should test something', ->

    #{defineContextStringInItBlock}
    nextCall()
"""


  it 'Checks case, which consists of it with describe message with done argument', ->
    coffeeScript = """
describe 'One test, one touch', ->
  it 'should test something and executes callback', (done) ->
    nextCall()
"""
    compileTest.preCompilerCallback(coffeeScript).should.equal """
#{defineContextString}
describe 'One test, one touch', ->
  it 'should test something and executes callback', (done) ->

    #{defineContextStringInItBlock}
    nextCall()
"""


  it 'Checks test-suite with multiple it-blocks', ->
    coffeeScript = """
describe 'Two tests, two touches', ->
  it 'should test first case', (done) ->
    firstCall()


  it 'should test second case', ->
    secondCall()
"""
    compileTest.preCompilerCallback(coffeeScript).should.equal """
#{defineContextString}
describe 'Two tests, two touches', ->
  it 'should test first case', (done) ->

    #{defineContextStringInItBlock}
    firstCall()


  it 'should test second case', ->

    #{defineContextStringInItBlock}
    secondCall()
"""
    
    
  it 'should test script with random it-letters in it', ->
    coffeeScript = """
describe 'It is simple test with it ', ->
  it 'should call it or not call it', ->
    itCallback(' it argument ->')
"""
    compileTest.preCompilerCallback(coffeeScript).should.equal """
#{defineContextString}
describe 'It is simple test with it ', ->
  it 'should call it or not call it', ->

    #{defineContextStringInItBlock}
    itCallback(' it argument ->')
"""
