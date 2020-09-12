path    = require 'path'
open    = require 'open'
request = require 'request'
urljoin = require 'url-join'
fs      = require 'fs'

{CompositeDisposable} = require 'atom'

handleError = (err) ->
  atom.notifications.addError '[Vale Server] could not connect.',
    detail: err
    dismissable: true

handleJSON = (content, instance, fixes, loc, styles, offset) ->
  feedback = JSON.parse(content.toString())
  messages = []

  for f, alerts of feedback
    for alert in alerts
      rule = alert.Check.split '.'
      floc = [
        [(alert.Line - 1) + offset, alert.Span[0] - 1]
        [(alert.Line - 1) + offset, alert.Span[1]]
      ]

      messages.push
        severity: if alert.Severity == 'suggestion' then 'info' else alert.Severity
        solutions: if fixes then suggestions(alert, floc, instance) else []
        location:
          file: loc
          position: floc
        excerpt: alert.Message
        linterName: "[Vale Server] #{alert.Check}"
        url: alert.Link
        description: alert.Description
        reference:
          file: path.join styles, rule[0], rule[1] + '.yml'

  messages

suggestions = (a, pos, path) ->
  fixes = []
  request.post
    url: urljoin(path, 'suggest'),
    form:
      alert: JSON.stringify(a)
  , (err, res, ret) ->
    if not err and res.statusCode is 200
      if ret
        for suggestion in JSON.parse(ret)['suggestions']
          if a.Action.Name is 'remove'
            # We need to add a character to avoid leaving a double space when
            # deleting.
            pos[0] = [pos[0][0], pos[0][1] - 1]
            console.log pos, a.Match
            fixes.push
              position: pos
              currentText: ' ' + a.Match
              replaceWith: suggestion
          else
            fixes.push
              position: pos
              currentText: a.Match
              replaceWith: suggestion

  fixes

module.exports =
  config:
    valePath:
      type: 'string'
      title: 'URL of your Vale Server instance.'
      default: 'http://127.0.0.1:7777'

    lintOnFly:
      type: 'boolean'
      title: 'Run Vale Server on file changes (not only after saving).'
      default: true

    offerSuggestions:
      type: 'boolean'
      title: 'Offer potential solutions to alerts using the \'Fix\' button.'
      default: true

    lintContext:
      type: 'integer'
      title: 'Only lint the active portion of a document. The three supported values are: -1 (applies to all files), 0 (disabled), n (applies to any file with lines >= n).'
      default: 0

  activate: =>
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.config.observe 'vale-server.valePath',
        (valePath) =>
          @valePath = valePath

    @subscriptions.add atom.config.observe 'vale-server.lintOnFly',
      (lintOnFly) =>
        @lintOnFly = lintOnFly

    @subscriptions.add atom.config.observe 'vale-server.offerSuggestions',
      (offerSuggestions) =>
        @offerSuggestions = offerSuggestions

    @subscriptions.add atom.config.observe 'vale-server.lintContext',
      (lintContext) =>
        @lintContext = lintContext

  deactivate: =>
      @subscriptions.dispose()

  provideLinter: =>
    provider =
      name: 'Vale Server'
      grammarScopes: ['*']
      scope: 'file'
      lintsOnChange: @lintOnFly

      lint: (textEditor) =>
        loc = textEditor.getPath()
        ext = path.extname(loc)

        output = ''
        styles = ''

        request.get
          url: urljoin(@valePath, 'path')
          json: true
        , (err, res, body) ->
          if not err and res.statusCode is 200
            styles = body.path

        runLinter = (resolve) =>
          instance = @valePath
          fixes = @offerSuggestions

          context = @lintContext
          if context < 0 || (context > 0 && textEditor.getLineCount() >= context)
            range = textEditor.getCurrentParagraphBufferRange()
            paragraph = textEditor.getTextInBufferRange(range)
            request.post
              url: urljoin(@valePath, 'vale'),
              form:
                format: ext
                text: paragraph,
            , (err, res, output) ->
              if not err and res.statusCode is 200
                offset = range.start.row
                resolve handleJSON(output, instance, fixes, loc, styles, offset)
              else
                handleError(err)
          else
            request.post
              url: urljoin(@valePath, 'file'),
              form:
                file: loc,
                path: path.dirname(loc)
            , (err, res, output) ->
              if not err and res.statusCode is 200
                  results = JSON.parse(output)
                  content = fs.readFileSync(results.path, 'utf8')
                  resolve handleJSON(content, instance, fixes, loc, styles, 0)
              else
                handleError(err)

        return new Promise (resolve, reject) =>
          runLinter(resolve)
