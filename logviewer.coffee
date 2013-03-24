express = require 'express'
mongoose = require 'mongoose'

app = express()

dbLogs = mongoose.createConnection 'mongodb://localhost/logs'

app.configure () ->
    app.use express.bodyParser()
    app.use express.methodOverride()
    app.use app.router
    app.use express.static(process.cwd() + '/public')
    app.use express.errorHandler({
        dumpExceptions: true,
        showStack: true
    })

Schema = mongoose.Schema

Log = new Schema { 
    message: String,
    exception: Schema.Types.Mixed,
}, collection: "logs_net"

LogModel = dbLogs.model 'Log', Log

# one log
app.get /^\/api\/log\/([0-9a-fA-F]{24})$/, (req, res) ->
    id = req.params[0]
    LogModel.findById id, (err, log) ->
        if !err
            res.send log
        else
            console.log err

# all logs
app.get '/api/log/:page?', (req, res) ->
    limitCount = 20
    page = req.params.page ? 1
    LogModel.find {}, "message exception timestamp level",
        skip: (page - 1) * limitCount
        limit: limitCount
        sort:
            timestamp: -1
        (err, logs) ->
            if !err
                res.send logs
            else
                console.log err
                res.send err

# logs by level
app.get '/api/log/:level/:page?', (req, res) ->
    limitCount = 20
    level = req.params.level
    page = req.params.page ? 1
    levels = ["debug", "info", "warn", "error", "fatal"]
    if (level in levels)
        LogModel.find { level: level.toUpperCase()}, "message exception timestamp level",
            skip: (page - 1) * limitCount
            limit: limitCount
            sort:
                timestamp: -1
            (err, logs) ->
                if !err
                    res.send logs
                else
                    console.log err
    else
        res.send "error"

# delete one log
app.delete /^\/api\/log\/([0-9a-fA-F]{24})$/, (req, res) ->
    id = req.params[0]
    LogModel.findById id, (err, logItem) ->
        if not err
            LogModel.remove _id: id, (err) ->
                if not err
                    res.send logItem
                else
                    console.log err
                    res.send err
        else
            console.log err
            res.send err

getErrorStats = (callback) ->
    map = () ->
        date = new Date(this.timestamp.getFullYear(), this.timestamp.getMonth(), this.timestamp.getDate())
        emit date, 1

    reduce = (key, values) ->
        total = 0
        for value in values
            total += value
        total

    command =
        map: map
        reduce: reduce
        query:
            level: "ERROR"
            timestamp:
                $gt: new Date(new Date().getFullYear(), new Date().getMonth(), 0)
    LogModel.mapReduce command, (err, results) ->
        callback results

getTopErrors = (callback) ->
    LogModel.aggregate
        $match:
            level: "ERROR"
    ,
        $group:
            _id: "$message"
            count:
                $sum: 1
    ,
        $sort:
            count: -1
    ,
        $limit: 5
    ,
        (err, result) ->
            callback result

app.get "/api/errorstats", (req, res) ->
    getErrorStats (result) ->
        res.send result

app.get "/api/gettoperrors", (req, res) ->
    getTopErrors (result) ->
        res.send result

app.get /^\/api\/errorstats\/([0-9a-fA-F]{24})$/, (req, res) ->
    id = req.params[0]
    LogModel.findById id, (err, log) ->
        if log.exception
            m =
                "exception.stackTrace": log.exception.stackTrace
        else
            m =
                "message": log.message
        LogModel.aggregate
            $match: m
        ,
            $group:
                _id:
                    dayOfMonth:
                        $dayOfMonth: "$timestamp"
                    month:
                        $month: "$timestamp"
                    year:
                        $year: "$timestamp"
                count: 
                    $sum: 1
        ,
            (err, result) ->
                for i in result
                    i._id = new Date(i._id.year, i._id.month, i._id.dayOfMonth)
                    i.value = i.count
                    delete i.count
                res.send result

app.listen 3000