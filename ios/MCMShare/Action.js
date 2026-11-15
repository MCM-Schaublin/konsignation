var Action = function() {};

Action.prototype = {
    run: function(arguments) {
        arguments.completionFunction({
            "text": document.body ? document.body.innerText : "",
            "url": document.URL,
            "title": document.title
        });
    },
    finalize: function(arguments) {}
};

var ExtensionPreprocessingJS = new Action;
