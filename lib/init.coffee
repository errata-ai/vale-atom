path    = require 'path'
request = require 'request'

{CompositeDisposable} = require 'atom'

module.exports =
  config:
    valePath:
      type: 'string'
      title: 'URL of your Vale Server instance.'
      default: 'http://127.0.0.1:7777'

    lintOnFly:
      type: 'boolean'
      title: 'Run Vale Server on change (not only after saving).'
      default: true

    grammarScopes:
      type: 'array'
      title: 'List of scopes Vale Server will lint.'
      default: [
        'source.gfm'
        'gfm.restructuredtext'
        'source.asciidoc'
        'text.md'
        'text.git-commit'
        'text.plain'
        'text.plain.null-grammar'
        'text.restructuredtext'
      ]

  activate: =>
    @subscriptions = new CompositeDisposable

    @subscriptions.add atom.config.observe 'vale-server.valePath',
        (valePath) =>
          @valePath = valePath

    @subscriptions.add atom.config.observe 'vale-server.lintOnFly',
      (lintOnFly) =>
        @lintOnFly = lintOnFly

    @subscriptions.add atom.config.observe 'vale-server.grammarScopes',
      (grammarScopes) =>
        @grammarScopes = grammarScopes

  deactivate: =>
      @subscriptions.dispose()

  provideLinter: =>
    provider =
      name: 'Vale Server'
      grammarScopes: @grammarScopes
      scope: 'file'
      lintsOnChange: @lintOnFly

      lint: (textEditor) =>
        filePath = textEditor.getPath()
        inputText = textEditor.getText()
        fileExtension = path.extname(filePath)
        fileDirectory = path.dirname(filePath)
        output = ''

        runLinter = (resolve) =>
          onError = ({error,handle}) =>
            atom.notifications.addError "Error running #{@valePath}",
              detail: "#{error.message}"
              dismissable: true
            handle()
            return []

          onReq = ({output}) =>
            if output.length <= 3 # if empty object
              output = "{\"stdin#{fileExtension}\":[]}"

            feedback = JSON.parse(output)["stdin#{fileExtension}"] or
              JSON.parse(output)['stdinunknown']
            messages = []
            for message in feedback
              atomMessageLine = message.Line - 1
              atomMessageRow = message.Span[0] - 1
              isDuplicate = messages.some (existingMessage) =>
                  existingMessage.range[0][0] == atomMessageLine and
                  existingMessage.range[0][1] == atomMessageRow
              if not isDuplicate
                messages.push
                  severity: if message.Severity == 'suggestion' then 'info' else message.Severity
                  text: message.Message
                  filePath: filePath
                  range: [
                    [atomMessageLine, atomMessageRow]
                    [atomMessageLine, message.Span[1]]
                  ]

              resolve messages

          request.post
            url: @valePath,
            form:
              format: fileExtension
              text: inputText
          , (err, res, body) ->
            if body
              onReq body
            else
              atom.notifications.addError "[Vale Server] could not connect to '#{@valePath}'.",
                detail: err
                dismissable: true

        return new Promise (resolve, reject) =>
          runLinter(resolve)
