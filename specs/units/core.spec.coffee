
declaration('error raised in describe')
.shouldFailWith /message/, ->
  describe 'failing declaration', ->
    throw new Error 'message'

virtualEnv('when unhandled exception is raised in example')
.shouldFailWith /0 assertions, 1 failure/, ->
  describe 'failing example', ->
    it -> throw new Error 'message'

virtualEnv('when unhandled exception is raised in example with expectations')
.shouldFailWith /1 assertion, 1 failure/, ->
  describe 'failing example with expectation', ->
    it 'should have been stopped', ->
      true.should be true
      throw new Error 'message'