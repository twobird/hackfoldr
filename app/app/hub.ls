angular.module 'hub.g0v.tw' <[ui.state firebase]>

.controller TagControl: <[$scope $state $location Hub]> ++ ($scope, $state, $location, Hub) ->
  $scope.$watch '$state.params.tag' (tag) ->
    $scope.tag = tag
    $scope.loadDisqus tag
  $scope <<< do
    projects:
      * name: \立法院
      * name: \meta
    people: Hub.people
    loadDisqus: (tag) ->
        if $location.host! is 'localhost'
            return
            window.disqus_developer = 1;

        window.disqus_shortname = 'g0vhub'
        window.disqus_identifier = encodeURIComponent "tag-#tag"
        window.disqus_url = "http://hack.g0v.tw/tag/#tag"
        window.disqus_title = "g0v.tw 》 tag  》#tag"
        if typeof DISQUS isnt 'undefined'
          DISQUS.reset do
            reload: true
            config: ->
              this.page <<< window{disqus_title, disqus_identifier, disqus_url}
        oldDsq = document.getElementById('disqusCommentScript');
        if(oldDsq)
            (document.getElementsByTagName('head')[0] ||
            document.getElementsByTagName('body')[0]).removeChild(oldDsq)
        console.log \url window.disqus_url
        ``
        // http://docs.disqus.com/developers/universal/
        (function() {
          var dsq = document.createElement('script'); dsq.type = 'text/javascript'; dsq.async = true;
          dsq.src = 'http://angularjs.disqus.com/embed.js';
          (document.getElementsByTagName('head')[0] ||
            document.getElementsByTagName('body')[0]).appendChild(dsq);
        })();
        ``

        angular.element document.getElementById 'disqus_thread' .html ''

.controller ProjectCtrl: <[$scope $state $location Hub angularFire]> ++ ($scope, $state, $location, Hub, angularFire) ->
    $scope <<< do
        people: Hub.people
        projects: Hub.projects
        opts: {}
        remove_tag: (thing, tag) ->
            thing.keywords = [t for t in thing.keywords when t isnt tag]
        add_tag: (thing) ->
            thing.keywords ?= []
            # XXX check duplicated
            thing.keywords.push $scope.opts.newtag
            $scope.opts.newtag = ''
            return false

    $scope.$watch '$state.params.projectName' (projectName) ->
        $scope.projectName = projectName
        promise = angularFire Hub.root.child("projects/#{projectName}"), $scope, 'project', {}

.controller PeopleCtrl: <[$scope $state Hub angularFire]> ++ ($scope, $state, Hub, angularFire) ->
    $scope.safeApply = (fn) ->
        phase = $scope.$root.$$phase
        if (phase is '$apply' || phase is '$digest')
            fn?!
        else
            $scope.$apply fn

    $scope <<< do
        remove_tag: (person, tag) ->
            person.tags = [t for t in person.tags when t isnt tag]
        add_tag: (person) ->
            person.tags ?= []
            # XXX check duplicated
            person.tags.push $scope.newtag
            $scope.newtag = ''
            return false
        projects: Hub.projects
        people: Hub.people
        auth: Hub.auth
        set-username: Hub.set-username
        login-and-merge: Hub.login-and-merge
        login-and-link: Hub.login-and-link
    $scope.$on 'event:auth-login' (e, {user}) -> $scope.safeApply ->
        promise = angularFire Hub.root.child("people/#{user.username}"), $scope, 'user', {}
        $scope.toSetUsername = false
    $scope.$on 'event:auth-logout' -> $scope.safeApply ->
        delete $scope.user
        $scope.toSetUsername = false
    $scope.$on 'event:auth-userNameRequired' (e, {existing}) -> $scope.safeApply ->
        $scope.toSetUsername = true
        $scope.usernameInUse = existing
        $scope.newUsername = Hub.auth-user?username

.factory Hub: <[$http angularFireCollection $rootScope]> ++ ($http, angularFireCollection, $rootScope) ->
    url = window.global.config.FIREBASE
    myDataRef = new Firebase(url)
    people = angularFireCollection myDataRef.child \people
    projects = angularFireCollection myDataRef.child \projects
    self = {}
    check-username = (username, always-prompt, cb) ->
        inuse <- myDataRef.child "people/#{username}" .once \value
        existing = inuse.val!
        if always-prompt || existing
            $rootScope.$broadcast 'event:auth-userNameRequired', {existing}
        cb?! unless existing

    self.set-username = (username) ->
        return unless self.auth-user
        <- check-username username, false
        # XXX: disallow if people/#username exists and we do not have the credentials listed in auth
        info = self.auth-user{displayName} <<< {tags: [], username}
        info.avatar = match self.auth-user.provider
        | 'github'
            [_, gravatar] = self.auth-user.avatar_url.match // https:\/\/secure.gravatar.com/avatar/(\w+) //
            "http://avatars.io/gravatar/#gravatar"
        | 'twitter'
            "http://avatars.io/twitter/#{self.auth-user.username}"
        else
            "http://avatars.io/#{self.auth-user.provider}/#{self.auth-user.id}"
        myDataRef
            ..child "auth-map/#{self.auth-user.provider}/#{self.auth-user.id}" .set {username}
            ..child "people/#{username}" .set info
            ..child "people/#{username}/auth/#{self.auth-user.provider}" .set self.auth-user{id, username}
        login-user <- myDataRef.child "people/#{username}" .once \value
        self.login-user = login-user.val!
        $rootScope.$broadcast 'event:auth-login', user: self.login-user

    self.login-and-merge = (provider) ->
        self.auth-merge = self.auth-user
        self.auth.login provider
    self.login-and-link = (provider) ->
        self.auth-link = self.auth-user
        self.auth-link-user = self.login-user
        self.auth.login provider
    self.auth = new FirebaseAuthClient myDataRef, (error, user) ->
        if error
            console.log error
        else if user
            self.auth-user = user
            auth <- myDataRef.child "auth-map/#{user.provider}/#{user.id}" .once \value
            if {username}? = auth.val!
                entry = myDataRef.child "people/#{username}"
                login-user <- entry.once \value
                if merge = self.auth-merge
                    newauth = { "#{merge.provider}": merge{id, username ? ''} }
                    entry.child 'auth' .update newauth
                    myDataRef.child "auth-map/#{merge.provider}/#{merge.id}" .set {username}
                    delete self.auth-merge
                self.login-user = login-user.val!
                $rootScope.$broadcast 'event:auth-login', user: self.login-user
            else
                if link = self.auth-link
                    username = self.auth-link-user.username
                    # XXX might need to reuse the token from self.auth-link to write
                    entry = myDataRef.child "people/#{username}"
                    #login-user <- entry.once \value
                    #self.login-user = login-user.val!
                    newauth = { "#{user.provider}": user{id, username ? ''} }
                    #$rootScope.$broadcast 'event:auth-login', user: self.login-user
                    entry.child 'auth' .update newauth
                    myDataRef.child "auth-map/#{user.provider}/#{user.id}" .set {username}
                    delete self.auth-link
                else
                    check-username self.auth-user.username, true
        else
            $rootScope.$broadcast 'event:auth-logout'
    self <<< do
        root: myDataRef
        people: people
        projects: projects
