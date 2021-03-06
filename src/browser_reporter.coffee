utils = spectacular.utils

ancestors = (node, block) ->
  parent = node.parentNode

  if hasClass parent, 'example-group'
    block.call this, parent
    ancestors parent, block

wrapNode = (node) ->
  if node.length? then node else [node]

hasClass = (nl, cls) ->
  nl = wrapNode nl

  Array::every.call nl, (n) -> ///(\s|^)#{cls}(\s|$)///.test n.className

addClass = (nl, cls) ->
  nl = wrapNode nl
  Array::forEach.call nl, (node) ->
    node.className += " #{cls}" unless hasClass node, cls

removeClass = (nl, cls) ->
  nl = wrapNode nl
  Array::forEach.call nl, (node) ->
    node.className = node.className.replace cls, ''

toggleClass = (nl, cls) ->
  nl = wrapNode nl
  Array::forEach.call nl, (node) ->
    if hasClass node, cls
      removeClass node, cls
    else
      addClass node, cls

fixNodeHeight = (nl) ->
  nl = wrapNode nl
  Array::forEach.call nl, (node) ->
    node.style.height = "#{node.clientHeight}px"

FILE_RE = -> /(http:\/\/.*\.(js|coffee)):(\d+)(:(\d+))*/g

class spectacular.SlidingObject
  constructor: (@target, @container) ->
    previousOnScroll = window.onscroll
    doc = document.documentElement
    body = document.body

    window.onscroll = =>
      do previousOnScroll if previousOnScroll?

      topMin = @getOffset @container
      topMax = topMin + @container.clientHeight - @target.clientHeight
      top = (doc and doc.scrollTop or body and body.scrollTop or 0)
      top = Math.min(topMax, Math.max(topMin, top + 100)) - topMin
      @target.style.top = "#{top}px"

  getOffset: (node) ->
    return node.offsetTop if node.nodeName.toLowerCase() is 'body'
    node.offsetTop + @getOffset node.parentNode

class spectacular.BrowserStackReporter extends spectacular.StackReporter
  @reports: 0

  constructor: (@error, @options) ->
    @id = BrowserStackReporter.reports
    BrowserStackReporter.reports += 1

  report: ->
    return '' unless @error.stack

    stack = @error.stack.split('\n').filter (line) -> /( at |@)/g.test line
    line = stack.shift()

    pre = """
      <pre id='pre_#{@id}_source' class='loading'></pre>
      <pre id='pre_#{@id}_stack'>#{@prepareStack stack}</pre>
    """

    @loadSource(line).then (msg) =>
      source = document.getElementById "pre_#{@id}_source"
      source.innerHTML = msg
      removeClass source, 'loading'
      fixNodeHeight source

      stackLinks = document.getElementById("pre_#{@id}_stack").querySelectorAll('a')
      Array::forEach.call stackLinks, (link) =>
        link.onclick = (e) =>
          e.preventDefault()
          e.stopImmediatePropagation()
          linkPre = link.parentNode.querySelector 'pre'
          if linkPre?
            toggleClass linkPre, 'hidden'
          else
            linkLine = link.textContent
            @loadSource(linkLine).then (msg) ->
              linkPre = document.createElement 'pre'
              linkPre.innerHTML = msg
              link.parentNode.appendChild linkPre

    pre

  prepareStack: (stack) ->
    stack = stack.map (s) -> "<span><a href='#' rel='stack'>#{utils.escape s}</a></span>"
    @formatStack stack

  loadSource: (stackLine) ->
    [match, url, e, line, c, column] = FILE_RE().exec stackLine

    column = @error.columnNumber + 1 if not column? and @error.columnNumber?

    @getLines(url, parseInt(line), parseInt(column))

class spectacular.BrowserReporter
  STATE_CHARS =
    pending: '*'
    skipped: 'x'
    failure: 'F'
    errored: 'E'
    success: '.'

  constructor: (@options) ->
    @errorsCounter = 1
    @failuresCounter = 1
    @errors = []
    @failures = []
    @skipped = []
    @pending = []
    @results = []
    @examples = []

    @reporter = document.createElement('div')
    @reporter.id = 'reporter'
    addClass @reporter, if @options.documentation then 'documentation' else 'progress'
    @reporter.innerHTML = """
      <header>
        <h1>Spectacular</h1>
        <h2>#{spectacular.version}</h2>
        <aside>
          <pre></pre>
          <p></p>
        </aside>
      </header>
      <section id="examples">
        <section id="controls">#{
          ['success', 'pending', 'errored', 'failure', 'skipped'].map((k) ->
            "<button class='toggle #{k}'>#{k}</button>"
          ).join '\n'
          }
        </section>
      </section>
      <footer></footer>
    """
    html = document.querySelector('html')
    buttons = @reporter.querySelectorAll 'button.toggle'
    Array::forEach.call buttons, (button) ->
      button.onclick = (e) ->
        toggleClass html, "hide-#{button.textContent}"
        toggleClass button, "off"



    @examplesContainer = @reporter.querySelector '#examples'
    @progress = @reporter.querySelector 'header pre'
    @counters = @reporter.querySelector 'header p'


    controls = @reporter.querySelector '#controls'
    @controlsScroller = new spectacular.SlidingObject controls, @examplesContainer

  onEnd: (event) =>
    html = document.querySelector 'html'
    runner = event.target
    window.resultReceived = true
    window.result = not @hasFailures()
    if result
      addClass html, 'success'
    else
      addClass html, 'failure'

    counters = @counters.querySelector('#counters')
    counters.innerHTML = "#{counters.innerHTML}, finished in #{@formatDuration runner.specsStartedAt, runner.specsEndedAt}"

  link: (example, id) ->
    link = document.createElement 'a'
    link.className = example.result.state
    link.setAttribute 'href', "#example_#{id}"
    link.setAttribute 'title', "##{id} #{example.fullDescription}"
    link.innerHTML = @stateChar example.result.state
    link

  stateChar: (state) -> STATE_CHARS[state]

  onResult: (event) =>
    html = document.querySelector 'html'

    example = event.target
    @results.push example.result
    @examples.push example
    @progress.appendChild @link example, @examples.length
    @counters.innerHTML = @formatCounters()
    switch example.result.state
      when 'pending' then @pending.push example
      when 'skipped' then @skipped.push example
      when 'errored'
        @errors.push example
        addClass html, 'hide-success'
      when 'failure'
        @failures.push example
        addClass html, 'hide-success'

    if @options.verbose
      console.log "  test #{example.description} > #{example.result.state}"

    if @options.documentation
      @formatDocumentationExample example
    else
      @formatProgressExample example

  formatDocumentationExample: (example) ->
    elders = example.ancestors
    elders.pop()

    reversed = []
    reversed.unshift a for a in elders

    node = @examplesContainer
    n = 0
    for ancestor in reversed

      id = ancestor.ownDescription.replace(/^[\s\W]+|[\s\W]+$/g, '').replace(/[^\w\d]+/g, '-').toLowerCase()
      continue if id is ''

      parent = node
      node = node.querySelector "##{id}"
      unless node?
        node = document.createElement 'section'
        node.id = id
        node.className = "example-group #{if ancestor.failed then 'failure' else 'success'} level#{n}"
        node.innerHTML = """
          <header title='#{ancestor.description}'>
            <h3>#{ancestor.ownDescription}</h3>
          </header>
        """
        parent.appendChild node

      n++

    id = @examples.length
    ex = document.createElement 'article'
    ex.id = "example_#{id}"
    ex.className = "example #{example.result.state} level#{n}"
    ex.dataset.id = id

    if example.result.expectations.length > 0
      ex.innerHTML = """
        <header title='#{example.description}'>
          <h4>#{example.ownDescription}</h4>
          <span class='result'>#{example.result.state}</span>
          <span class='time'><span class='icon-time'></span>#{example.duration / 1000}s</span>
        </header>
        <div class="expectations">
          #{(@formatExpectation e for e in example.result.expectations).join('')}
        </div>
      """
    else
      ex.innerHTML = """
        <header title='#{example.description}'>
          <h4>#{example.ownDescription}</h4>
          <span class='result'>#{example.result.state}</span>
          <span class='time'><span class='icon-time'></span>#{example.duration}s</span>
        </header>
        #{
          if example.reason?
            "<aside>
              <pre>#{utils.escapeDiff example.reason.message}</pre>
              #{ if example.reason? then @traceSource example.reason else ''}
            </aside>"
          else ''
        }
      """


    ex.onclick = -> toggleClass ex, 'closed'

    node.appendChild ex
    if example.failed
      ancestors ex, (node) ->
        if hasClass node, 'success'
          removeClass node, 'success'
          addClass node, 'failure'

    pres = ex.querySelectorAll('pre:not([id])')
    Array::forEach.call pres, (node) -> fixNodeHeight node
    addClass ex, 'closed'
    setTimeout (-> addClass ex, 'animate'), 100



  formatProgressExample: (example) ->
    id = @examples.length
    ex = document.createElement 'article'
    ex.id = "example_#{id}"
    ex.className = "example #{example.result.state}"
    ex.dataset.id = id

    if example.result.expectations.length > 0
      ex.innerHTML = """
        <header>
          <h4>#{example.description}</h4>
          <span class='result'>#{example.result.state}</span>
          <span class='time'><span class='icon-time'></span>#{example.duration / 1000}s</span>
        </header>
        <div class="expectations">
          #{(@formatExpectation e for e in example.result.expectations).join('')}
        </div>
      """
    else
      ex.innerHTML = """
        <header>
          <h4>#{example.description}</h4>
          <span class='result'>#{example.result.state}</span>
          <span class='time'><span class='icon-time'></span>#{example.duration}s</span>
        </header>
        #{
          if example.reason?
            "<aside>
              <pre>#{utils.escapeDiff example.reason.message}</pre>
              #{ if example.reason? then @traceSource example.reason else ''}
            </aside>"
          else ''
        }
      """

    ex.onclick = -> toggleClass ex, 'closed'
    @examplesContainer.appendChild ex
    pres = ex.querySelectorAll('pre:not([id])')
    Array::forEach.call pres, (node) -> fixNodeHeight node
    addClass ex, 'closed'
    setTimeout (-> addClass ex, 'animate'), 100

  formatExpectation: (expectation) ->
    """
    <div class="expectation #{if expectation.success then 'success' else 'failure'}" title="#{expectation.example.description} #{expectation.description}">
      <h5>#{expectation.description}</h5>
      <pre>#{utils.escapeDiff expectation.message}</pre>
      #{ if expectation.trace? then @traceSource expectation.trace else ''}
    </div>
    """

  traceSource: (error) ->
    (new spectacular.BrowserStackReporter error, @options).report()

  formatCounters: ->
    failures = @failures.length
    errored = @errors.length
    skipped = @skipped.length
    pending = @pending.length
    success = @examples.length - failures - errored - pending - skipped
    assertions = @results.reduce ((a, b) -> a + b.expectations.length), 0
    "<span id='counters'>
    #{@formatResults success, failures, errored, skipped, pending, assertions}
    </span>"

  formatResults: (s, f, e, sk, p, a) ->
    he = f + e
    "#{@formatCount s, 'success', 'success', @toggle he, 'success'},
    #{@formatCount a, 'assertion', 'assertions', @toggle he, 'success'},
    #{@formatCount f, 'failure', 'failures', @toggle he, 'success', 'failure'},
    #{@formatCount e, 'error', 'errors', @toggle e, 'success', 'errored'},
    #{@formatCount sk, 'skipped', 'skipped', @toggle sk, 'success', 'skipped'},
    #{@formatCount p, 'pending', 'pending', @toggle p, 'success', 'pending'}".replace /\s+/g, ' '

  formatCount: (value, singular, plural, color) ->
    s = if value is 0
        plural
      else if value is 1
        singular
      else
        plural

    if color?
      s = "<span class='#{color}'>#{value}</span> #{s}"
    else
      s = "<span>#{value}</span> #{s}"
    s
  toggle: (value, c1, c2) -> if value then c2 else c1

  formatDuration: (start, end) ->
    duration = (end.getTime() - start.getTime()) / 1000
    duration = "<span class='yellow'>#{Math.max 0, duration}s</span>"
    duration

  hasFailures: ->
    @results.some (result) -> result.state in ['failure', 'skipped', 'errored']

  appendToBody: -> document.querySelector('body').appendChild @reporter

cache = {}
loaders = {}

window.options = window.options or {}

defaults =
  coffee: false
  verbose: false
  profile: false
  trace: true
  longTrace: false
  showSource: true
  documentation: false
  matchersRoot: './specs/support/matchers'
  helpersRoot: './specs/support/helpers'
  fixturesRoot: './specs/support/fixtures'
  noMatchers: false
  noHelpers: false
  colors: true
  random: true
  seed: null
  server: false
  globs: []

window.options[k] = v for k,v of defaults when not k of window.options

window.paths = window.paths or []

options.loadFile = (file) ->

  promise = new spectacular.Promise

  if file of cache
    setTimeout (-> promise.resolve cache[file]), 0
    return promise

  if file of loaders
    loaders[file].push (data) -> promise.resolve data
    return promise

  req = new XMLHttpRequest()
  req.onload = ->
    data = @responseText
    loaders[file].forEach (f) -> f data

  listener = (data) -> promise.resolve cache[file] = data
  loaders[file] = [listener]

  req.open 'get', file, true
  req.send()

  promise

spectacular.env = new spectacular.Environment(window.options)
spectacular.env.globalize()
spectacular.env.runner.loadStartedAt = new Date()
spectacular.env.runner.paths = window.paths

window.env = spectacular.env

currentWindowOnload = window.onload
window.onload = ->
  do currentWindowOnload if currentWindowOnload?
  utils = spectacular.utils

  if options.verbose
    console.log utils.indent utils.inspect window.options
    console.log utils.indent utils.inspect window.paths
    console.log '\n  Scripts loaded:'
    scripts = document.querySelectorAll('script[src]')
    for s in scripts
      console.log "    #{s.attributes.getNamedItem("src")?.value}"

    console.log ''

  reporter = new spectacular.BrowserReporter(options)
  reporter.appendToBody()
  spectacular.env.runner.on 'result', reporter.onResult
  spectacular.env.runner.on 'end', reporter.onEnd
  spectacular.env.runner.loadEndedAt = new Date()
  spectacular.env.runner.specsStartedAt = new Date()

  spectacular.env.run().fail (reason) ->
    console.log reason

