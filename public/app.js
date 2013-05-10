var showSpinner = function (selector) {
    selector = selector || ".js-detail";
    $(selector).html('<center><img src="spinner.gif"></center>');
};
var Model = Backbone.Model.extend({
    idAttribute : "_id"
});

var Collection = Backbone.Collection.extend({        
    model : Model,
    initialize : function(options){
        this.level = options.level;
        this.page = options.page ? parseInt(options.page) : 1;
    },
    url : function(){
        var u =  this.level ? "/api/log/" + this.level : "/api/log";
        u += "/" + this.page;
        return u;
    },
    nextPage : function(){
        this.page += 1;
        this.fetch()
    },
    prevPage : function(){
        if(this.page == 1)
            return false;
        this.page -= 1;
        this.fetch()
    }
});  

var ErrorStatsModel = Backbone.Collection.extend({
    initialize: function(options){
        this.id = options.id;
    },
    url: function() {
        if(this.id)
            return "/api/errorstats/" + this.id;
        else
            return "/api/errorstats";
    }
});

var TopErrorsModel = Backbone.Collection.extend({
    url: "/api/gettoperrors"
});

var TopErrorsView = Backbone.View.extend({
    template: Hogan.compile($("#template-top-error-item").html()),
    render: function() {
        var data = this.collection.toJSON(), html = "";
        for (var i = 0; i < data.length; i++) {
            html += this.template.render(data[i]);
        };
        $(this.el).html('<table class="table table-bordered table-striped"><tbody>' + html + '</tbody></table>');
        return this;
    }
});   

var ErrorStatsView = Backbone.View.extend({
    render: function() {
        var data = this.collection.toJSON();
        new Morris.Line({
            element: this.$el,
            data: data,
            xkey: '_id',
            ykeys: ['value'],
            labels: ['Value'],
            xLabels: ["day"],
            xLabelFormat: function (x) { 
                return moment(x).format('D MMMM');
            },
            hoverCallback: function (index, options) {
                var row = options.data[index];
                var str = moment(row._id).format('LL');
                str += "<br>Количество: " + row.value;
                return str;
            }
        });
    }
});   

var DashboardView = Backbone.View.extend({
    template : Hogan.compile($("#template-dashboard").html()),
    render : function() {
        var self = this;
        $(this.el).html(this.template.render());          

        var errorStatsModel = new ErrorStatsModel({});
        errorStatsModel.fetch({
            success: function(){
                var errorStatsView = new ErrorStatsView({
                    el : self.$el.find(".js-place-for-graph"), 
                    collection : errorStatsModel
                });
                errorStatsView.render();
            }
        });

        var topErrorsModel = new TopErrorsModel();
        topErrorsModel.fetch({
            success: function(){
                var topErrorsView = new TopErrorsView({
                    el : self.$el.find(".js-place-for-top-errors-stats"),
                    collection :topErrorsModel
                });
                topErrorsView.render();
            }
        });
        return this;
    }
});

var View = Backbone.View.extend({
    templates : {
        "index" : Hogan.compile($("#template-index").html()),
        "row" : Hogan.compile($("#template-table-row").html())
    },
    events :{
        "click .js-next" : "nextPage",         
        "click .js-prev" : "prevPage",
        "click .js-delete-item" : "onDeleteItemClick"
    },

    initialize : function (options) {
        this.collection.on("reset", this.renderCollection, this);
        this.collection.on("add", this.collectionAdded, this);
        this.eventObject = options.eventObject;
        this.eventObject.on("next", this.nextPage, this);
        this.eventObject.on("prev", this.prevPage, this);
        this.eventObject.on("addLogs", this.logsAdded, this);
    },
    logsAdded: function(logs){
        logs = JSON.parse(logs);
        if(logs.length){
            this.collection.add(logs);
            lastTimestamp = _.first(logs).timestamp;
            sock.send(lastTimestamp);
        }
    },
    prevPage : function(){
        showSpinner("tbody");
        this.collection.prevPage();
        return false;            
    },
    nextPage : function(){
        showSpinner("tbody");
        this.collection.nextPage();
        return false;            
    },
    onDeleteItemClick : function(e) {
        var target = $(e.target);
        var id = target.data("id");
        var m = this.collection.find(function(m){
            return m._id = id;
        });
        m.url = function(){return "/api/log/"+id;}
        m.destroy({
            success : function() {
                target.closest("tr").hide("explode", {}, 500);
            }
        });
        return false;            
    },
    render : function() {
        $(this.el).html(this.templates["index"].render());
        this.renderCollection();
        return this;
    },

    collectionAdded: function(logs){
        var self = this, html = "";
        var c = logs.toJSON();
        var message = c.message;
        var id = message.match(/[0-9a-fA-F]{24}/);
        message = message.replace(/[0-9a-fA-F]{24}/, '<a href="/api/events/' + id + '" target="_blank">@' + id + '</a>');                
        c.fromNow = moment(c.timestamp).fromNow();
        c.timestamp = moment(c.timestamp).format("HH:mm:ss, D MMMM YYYY");
        c.message = message;
        c.level = c.level.replace(/\w\S*/g, function(txt){return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase();})
        html += self.templates["row"].render(c);
        $(this.el).find("tbody").prepend(html);
        this.$("span[data-toggle='tooltip']").tooltip();
        return this;
    },

    renderCollection : function(){
        var self = this, html = "";
        if(_.first(this.collection.toJSON()))
            window.lastTimestamp = _.first(this.collection.toJSON()).timestamp;
        _.each(this.collection.toJSON(), function(c){
            c = self.extendContext(c);
            html += self.templates["row"].render(c);
        });
        $(this.el).find("tbody").html(html);
        this.$("span[data-toggle='tooltip']").tooltip();
        this.changeNavButtonUrl();            
        return this;
    },

    extendContext: function(c){
        var message = c.message;
        var id = message.match(/[0-9a-fA-F]{24}/);
        message = message.replace(/[0-9a-fA-F]{24}/, '<a href="/api/events/' + id + '" target="_blank">@' + id + '</a>');                
        c.fromNow = moment(c.timestamp).fromNow();
        c.timestamp = moment(c.timestamp).format("HH:mm:ss, D MMMM YYYY");
        c.message = message;
        c.level = c.level.replace(/\w\S*/g, function(txt){return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase();})
        return c;
    },

    changeNavButtonUrl : function(){
        var level = this.collection.level ? this.collection.level : "",
            page = this.collection.page;
        r.navigate(level + "/" + page);
        this.$(".js-next").prop("href", "#" + level + "/" + (page + 1));
        this.$(".js-prev").prop("href", "#" + level + "/" + (page - 1));
    },

    close : function(){
        this.off();
        $(this.el).off();
        this.collection.off();
        this.eventObject.off("next", this.nextPage, this);
        this.eventObject.off("prev", this.prevPage, this);
    }
});

var DetailModel = Backbone.Model.extend({
    urlRoot : "/api/log"
});

var DetailView = Backbone.View.extend({
    template : Hogan.compile($("#template-detail").html()),
    initialize : function () {
        
    },
    render : function() {
        var context = this.model.toJSON();            
        context.fromNow = moment(context.timestamp).fromNow();
        context.timestamp = moment(context.timestamp).format("HH:mm:ss, D MMMM YYYY");
        $(this.el).html(this.template.render(context));

        var errorStatsModel = new ErrorStatsModel({id : this.model.get("id")}),
            self = this;
        errorStatsModel.fetch({
            success: function(){
                var errorStatsView = new ErrorStatsView({
                    el : self.$el.find(".js-place-for-graph"), 
                    collection : errorStatsModel
                });
                errorStatsView.render();
            }
        });

        return this;
    }
});   

var Router = Backbone.Router.extend({
  routes: {
    "": "index",
    "dashboard": "dashboard",
    ":page": "index",
    "log/:id": "log",
    ":level/:page": "logs",
    ":level":"logs"
  },

  index : function(page){
    this.logs(null, page);
  },

  logs : function(level, page){
    showSpinner();
    page = page && page > 0 ? page : 1; 
    var levels = ["debug","info","warn", "error","fatal"], self = this;
    var hasLevel = level != null && _.indexOf(levels, level) > -1;
    var logs = hasLevel ? new Collection({level : level, page : page }) : new Collection({page : page});

    logs.fetch({
        success : function(){
            var view = new View({el : $(".js-view"), collection : logs, eventObject : eventObject });                
            self.showView(view);
        }
    });
  },

  log : function(id){
    showSpinner();
    var m = new DetailModel({id : id}), self = this;
    m.fetch({
        success : function(){
            var view = new DetailView({el : $(".js-detail"), model : m});
            self.showView(view);
        }
    });
  },

  dashboard : function(){
    showSpinner();
    var view = new DashboardView({el : $(".js-detail")});
    this.showView(view);
  },

  showView : function(view){
    if (this.currentView && this.currentView.close)
        this.currentView.close();

    this.currentView = view;
    view.render();
    return view;
    }
});