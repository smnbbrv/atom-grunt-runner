###
Nicholas Clawson -2014

The bottom toolbar. In charge handling user input and implementing
various commands. Creates a SelectListView and launches a task to
discover the projects grunt commands. Logs errors and output.
Also launches an Atom BufferedProcess to run grunt when needed.
###

{View, BufferedProcess, Task, $} = require 'atom'
ListView = require './task-list-view'

module.exports = class ResultsView extends View

    path: null,
    process: null,
    taskList: null,

    # html layout
    @content: ->
        @div class: 'grunt-runner-resizer tool-panel panel-bottom', =>
          @div class: 'grunt-runner-resizer-handle'
          @div class: 'grunt-runner-results tool-panel native-key-bindings', =>
              @div outlet:'status', class: 'grunt-panel-heading', =>
                  @div class: 'btn-group', =>
                      @button outlet:'startstopbtn', click:'startStopAction', class:'btn', 'Start Grunt'
                      @button outlet:'logbtn', click:'toggleLog', class:'btn', 'Toggle Log'
                      @button outlet:'panelbtn', click:'togglePanel', class:'btn', 'Hide'
              @div outlet:'panel', class: 'panel-body padded closed', =>
                  @ul outlet:'errors', class: 'list-group'

    # called after the view is constructed
    # initialize list and triggers processing of the gruntfile
    initialize:(state = {}) ->
        view = @

        atom.project.on 'path-changed', -> view.parseGruntFile()

        @taskList = new ListView @startProcess.bind(@), state.taskList
        @on 'mousedown', '.grunt-runner-resizer-handle', (e) => @resizeStarted(e)

        @startstopbtn.setTooltip "Start", command: 'grunt-runner:run'
        @logbtn.setTooltip "", command: 'grunt-runner:toggle-log'
        @panelbtn.setTooltip "", command: 'grunt-runner:toggle-panel'

        @parseGruntFile()


    # launches a task to parse the projects gruntfile if it exists
    parseGruntFile: ->
        @path = atom.project.getPath()
        view = @

        # clear panel output and tasklist items
        @emptyPanel()
        @taskList.clearItems()
        @status.attr 'data-status', null

        if !@path
            @addLine "No project opened."
        else
            Task.once require.resolve('./parse-config-task'), @path+'/gruntfile', ({error, tasks})->

                # log error or add panel to workspace
                if error
                    console.warn "grunt-runner: #{error}"
                    view.addLine "Error loading gruntfile: #{error}", "error"
                    view.toggleLog()
                else
                    view.addLine "Grunt file parsed, found #{tasks.length} tasks"
                    view.togglePanel()
                    view.taskList.addItems tasks

    startStopAction: ->
        return @toggleTaskList() if @process == null
        return @stopProcess()

    setStartStopBtn:(isRunning) ->
        if isRunning
            @.startstopbtn.text 'Stop'
            @.startstopbtn.setTooltip "", command: 'grunt-runner:stop'
        else
            @.startstopbtn.text 'Start'
            @.startstopbtn.setTooltip "", command: 'grunt-runner:run'

    # called to start the process
    # task name is gotten from the input element
    startProcess:(task) ->
        @stopProcess()
        @emptyPanel()
        @toggleLog() if @panel.hasClass 'closed'
        @status.attr 'data-status', 'loading'

        @addLine "Running : grunt #{task}", 'subtle'

        @.setStartStopBtn true

        @gruntTask task, @path

    # stops the current process if it is running
    stopProcess:(noMessage) ->
        @addLine 'Grunt task was ended', 'warning' if @process and not @process?.killed and not noMessage
        @process?.kill()
        @process = null
        @status.attr 'data-status', null
        @.setStartStopBtn false

    # toggles the visibility of the entire panel
    togglePanel: ->
        return atom.workspaceView.prependToBottom @ unless @.isOnDom()
        return @detach() if @.isOnDom()

    # toggles the visibility of the log
    toggleLog: ->
        @panel.toggleClass 'closed'

    # toggles the visibility of the tasklist
    toggleTaskList: ->
        return @taskList.attach() unless @taskList.isOnDom()
        return @taskList.cancel()


    # adds an entry to the log
    # converts all newlines to <br>
    addLine:(text, type = "plain") ->
        [panel, errorList] = [@panel, @errors]
        text = text.replace /\ /g, '&nbsp;'
        text = @colorize text
        text = text.trim().replace /[\r\n]+/g, '<br />'
        if not text.empty
            stuckToBottom = errorList.height() - panel.height() - panel.scrollTop() == 0
            errorList.append "<li class='text-#{type}'>#{text}</li>"
            panel.scrollTop errorList.height() if stuckToBottom

    # clears the log
    emptyPanel: ->
        @errors.empty()

    # returns a JSON object representing the state of the view
    serialize: ->
        return taskList: @taskList.serialize()

    # bash colors to html
    colorize:(text) ->
        text = text.replace /\[1m(.+?)(\[.+?)/g, '<span class="strong">$1</span>$2'
        text = text.replace /\[4m(.+?)(\[.+?)/g, '<span class="underline">$1</span>$2'
        text = text.replace /\[31m(.+?)(\[.+?)/g, '<span class="red">$1</span>$2'
        text = text.replace /\[32m(.+?)(\[.+?)/g, '<span class="green">$1</span>$2'
        text = text.replace /\[33m(.+?)(\[.+?)/g, '<span class="yellow">$1</span>$2'
        text = text.replace /\[36m(.+?)(\[.+?)/g, '<span class="cyan">$1</span>$2'
        text = text.replace /\[90m(.+?)(\[.+?)/g, '<span class="gray">$1</span>$2'
        text = @stripColorCodes text
        return text

    # remove invalid color codes
    stripColorCodes:(text) ->
        return text.replace /\[[0-9]{1,2}m/g, ''

    # removed color commands
    stripColors:(text) ->
        # borrowed from
        # https://github.com/Filirom1/stripcolorcodes (MIT license)
        return text.replace /\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]/g, ''

    # launches an Atom BufferedProcess
    gruntTask:(task, path) ->
        stdout = (out) ->
            @addLine out
        stderr = (err) ->
            @addLine err, 'error'
        exit = (code) ->
            atom.beep() unless code == 0
            @addLine "Grunt exited: code #{code}.", if code == 0 then 'success' else 'error'
            @status.attr 'data-status', if code == 0 then 'ready' else 'error'
            @stopProcess true

        try
            @process = new BufferedProcess
                command: 'grunt'
                args: [task]
                options: {cwd: path}
                stdout: stdout.bind @
                exit: exit.bind @
        catch e
            # this never gets caught...
            @addLine "Could not find grunt command. Make sure to set the path in the configuration settings.", "error"
            @stopProcess()

    resizeStarted: =>
        $(document.body).on('mousemove', @resizeGruntRunnerView)
        $(document.body).on('mouseup', @resizeStopped)

    resizeStopped: =>
        $(document.body).off('mousemove', @resizeGruntRunnerView)
        $(document.body).off('mouseup', @resizeStopped)

    resizeGruntRunnerView:(event) =>
        height = $(document.body).height() - event.pageY - $('.status-bar').height()
        @height(height)
