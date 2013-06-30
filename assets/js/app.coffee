showSpinner = (selector) ->
    $(selector || ".js-detail").html '<center><img src="spinner.gif"></center>'

class BaseModel extends Backbone.Model
    idAttribute: "_id"

class BaseCollection extends Backbone.Collection
    model: BaseModel
    
    initialize: (options) ->
        @level = options.level
        @page = if options.page then parseInt(options.page) else 1

    url: () ->
        if @level then "/api/log/#{@level}/#{@page}" else "/api/log/#{@page}"

    nextPage: () ->
        @page += 1
        @fetch reset: true

    prevPage: () ->
        return false if not @canPrev()            
        @page -= 1
        @fetch reset: true

    canPrev: () ->
        return @page > 1

# BaseView

class BaseView extends Backbone.View
    templates:
        "index": Hogan.compile($("#template-index").html())
        "row": Hogan.compile($("#template-table-row").html())

    events:
        "click .js-next": "nextPage"
        "click .js-prev": "prevPage"
        "click .js-delete-item": "onDeleteItemClick"

    initialize: (options) ->
        @collection.on "reset", @renderCollection, @
        @collection.on "add", @collectionAdded, @
        @eventObject = options.eventObject
        @eventObject.on "next", @nextPage, @
        @eventObject.on "prev", @prevPage, @
        @eventObject.on "addLogs", @logsAdded, @
    
    logsAdded: (logs) ->
        logs = JSON.parse(logs)
        if logs.length
            @collection.add(logs)
            lastTimestamp = _.first(logs).timestamp
            sock.send(lastTimestamp)

    prevPage: ->
        return false if not @collection.canPrev()

        showSpinner "tbody"
        @collection.prevPage()
        return false
    
    nextPage: ->
        showSpinner "tbody"
        @collection.nextPage()
        return false   
    
    onDeleteItemClick: (e) ->
        target = $(e.target)
        id = target.data "id"
        m = @collection.find (m) ->
            return m._id = id

        m.url = ->
            return "/api/log/" + id
        m.destroy
            success: ->
                target.closest("tr").hide("explode", {}, 500).remove()
        return false 
    
    render: ->
        $(@el).html @templates["index"].render()
        @renderCollection()
        this
    
    collectionAdded: (logs) ->
        self = @
        html = ""
        c = logs.toJSON()
        message = c.message
        id = message.match(/[0-9a-fA-F]{24}/)
        message = message.replace(/[0-9a-fA-F]{24}/, '<a href="/api/events/' + id + '" target="_blank">@' + id + '</a>')
        c.fromNow = moment(c.timestamp).fromNow()
        c.timestamp = moment(c.timestamp).format("HH:mm:ss, D MMMM YYYY");
        c.message = message;
        c.level = c.level.replace /\w\S*/g, (txt) ->
            return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase()
        html += self.templates["row"].render(c)
        $(@el).find("tbody").prepend html
        $(@el).find("span[data-toggle='tooltip']").tooltip()
        this

    renderCollection: ->
        self = this
        html = ""
        if _.first(@collection.toJSON())
            window.lastTimestamp = _.first(@collection.toJSON()).timestamp
        _.each @collection.toJSON(), (c) ->
            c = self.extendContext(c)
            html += self.templates["row"].render(c)

        $(this.el).find("tbody").html(html)
        $(@el).find("span[data-toggle='tooltip']").tooltip()
        @changeNavButtonUrl();            
        this

    extendContext: (c) ->
        message = c.message
        id = message.match(/[0-9a-fA-F]{24}/)
        message = message.replace(/[0-9a-fA-F]{24}/, '<a href="/api/events/' + id + '" target="_blank">@' + id + '</a>')
        level = c.level.replace /\w\S*/g, (txt) ->
            txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase()
        _.extend c,
            fromNow: moment(c.timestamp).fromNow()
            timestampPretty: moment(c.timestamp).format("HH:mm:ss, D MMMM YYYY")
            message: message
            level: level
    
    changeNavButtonUrl: ->
        level = if @collection.level then @collection.level else ""
        page = @collection.page
        r.navigate(level + "/" + page)
        $(@el).find(".js-next").prop("href", "#" + level + "/" + (page + 1))
        $(@el).find(".js-prev").prop("href", "#" + level + "/" + (page - 1))
    
    close: ->
        @off()
        # $(@el).off()
        @collection.off()
        @eventObject.off "next", @nextPage, @
        @eventObject.off "prev", @prevPage, @
        @eventObject.off "addLogs", @logsAdded, @

# TopErrors

class TopErrorsModel extends Backbone.Collection
    url: "/api/gettoperrors"

class TopErrorsView extends Backbone.View
    template: Hogan.compile $("#template-top-error-item").html()
    render: ->
        data = @collection.toJSON()
        html = "";
        for d in data
            html += @template.render d
        $(@el).html '<table class="table table-bordered table-striped"><tbody>' + html + '</tbody></table>'

# Details

class DetailModel extends Backbone.Model
    urlRoot: "/api/log"

class DetailView extends Backbone.View
    template: Hogan.compile($("#template-detail").html())

    render: ->
        context = @model.toJSON()        
        id = context.message.match(/[0-9a-fA-F]{24}/)
        context.exception.browser = JSON.stringify(context.exception.browser) if context.isJs
        _.extend context,
            message: context.message.replace /[0-9a-fA-F]{24}/, '<a href="/api/events/' + id + '" target="_blank">@'+ id + '</a>'
            fromNow: moment(context.timestamp).fromNow()
            timestamp: moment(context.timestamp).format("HH:mm:ss, D MMMM YYYY")
        $(this.el).html this.template.render(context)

        errorStatsModel = new ErrorStatsModel id : @model.get("id")
        self = this
        errorStatsModel.fetch
            success: ->
                errorStatsView = new ErrorStatsView
                    el: self.$el.find(".js-place-for-graph")
                    collection: errorStatsModel
                errorStatsView.render()

        this

# ErrorStats

class ErrorStatsModel extends Backbone.Collection
    url: "/api/errorstats"

class ErrorStatsView extends Backbone.View
    render: ->
        data = @collection.toJSON()
        new Morris.Line
            element: @el
            data: data
            xkey: '_id'
            ykeys: ['value']
            labels: ['Value']
            xLabels: ["day"]
            xLabelFormat: (x) ->
                return moment(x).format('D MMMM')                
            hoverCallback: (index, options) ->
                row = options.data[index]
                str = moment(row._id).format('LL')
                str += "<br>Ошибок: " + row.value;
                return str

# DashboardView
                
class DashboardView extends Backbone.View
    template: Hogan.compile($("#template-dashboard").html())
    
    render: ->
        self = @
        $(@el).html @template.render()
        
        errorStatsModel = new ErrorStatsModel()
        errorStatsModel.fetch
            success: ->
                errorStatsView = new ErrorStatsView
                    el: self.$el.find(".js-place-for-graph")
                    collection: errorStatsModel
                errorStatsView.render()
        
        topErrorsModel = new TopErrorsModel()
        topErrorsModel.fetch
            success: ->
                topErrorsView = new TopErrorsView
                    el: self.$el.find(".js-place-for-top-errors-stats")
                    collection: topErrorsModel
                topErrorsView.render()       
        this

class window.Router extends Backbone.Router
    routes:
        "": "index"
        "dashboard": "dashboard"
        ":page": "index"
        "log/:id": "log"
        ":level/:page": "logs"
        ":level":"logs"

    index: (page) ->
        @logs null, page

    logs: (level, page) ->
        showSpinner()
        page = if page then page else 1
        levels = ["debug", "info", "warn", "error", "fatal", "jserror", "dotneterror"]
        self = @
        hasLevel = yes if level in levels
        logs = if hasLevel then new BaseCollection {level: level, page: page } else new BaseCollection page: page

        logs.fetch
            success: ->
                view = new BaseView
                    el: $(".js-view")
                    collection: logs
                    eventObject: eventObject
                self.showView view
    
    log: (id) ->
        showSpinner()
        m = new DetailModel id: id
        self = @
        m.fetch
            success: ->
                view = new DetailView
                    el: $(".js-detail")
                    model: m
                self.showView view

    dashboard: ->
        showSpinner()
        view = new DashboardView el: $(".js-detail")
        @showView view

    showView: (view) ->
        @currentView.close() if @currentView?.close
        @currentView = view
        @currentView.render()