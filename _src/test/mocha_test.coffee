fs = require "fs"

should = require "should"
clone = require "lodash/clone"
{ stringify } = JSON

pkg = JSON.parse fs.readFileSync("package.json")

nodeCache = require "../"
{ randomNumber, randomString, diffKeys } = require "./helpers"

localCache = new nodeCache({
	stdTTL: 0
})

localCacheNoClone = new nodeCache({
	stdTTL: 0,
	useClones: false,
	checkperiod: 0
})

localCacheMaxKeys = new nodeCache({
	maxKeys: 2
})

localCacheTTL = new nodeCache({
	stdTTL: 0.3,
	checkperiod: 0
})

localCacheNoDelete = new nodeCache({
	stdTTL: 0.3,
	checkperiod: 0
	deleteOnExpire: false
})

BENCH = {}

# just for testing disable the check period
localCache._killCheckPeriod()

# store test state
state = {}

describe "`#{pkg.name}@#{pkg.version}` on `node@#{process.version}`", () ->

	after ->
		txt = "Benchmark node@#{process.version}:"
		for type, ops of BENCH
			txt += "\n   - #{type}: #{ops.toFixed(1)} ops/s"
		console.log txt
		return

	describe "general sync-style", () ->
		before () ->
			localCache.flushAll()

			state =
				start: clone localCache.getStats()
				value: randomString 100
				value2: randomString 100
				value3: randomString 100
				key: randomString 10
				obj:
					a: 1
					b:
						x: 2
						y: 3
			return

		it "set key", () ->
			res = localCache.set state.key, state.value, 0
			true.should.eql res
			1.should.eql localCache.getStats().keys - state.start.keys
			return

		it "get key", () ->
			res = localCache.get state.key
			state.value.should.eql res
			return

		it "get key names", () ->
			res = localCache.keys()
			[state.key].should.eql res
			return

		it "has key", () ->
			res = localCache.has(state.key)
			res.should.eql true
			return

		it "does not have key", () ->
			res = localCache.has('non existing key')
			res.should.eql false
			return

		it "delete an undefined key", () ->
			count = localCache.del "xxx"
			0.should.eql count
			return

		it "update key (and get it to check if the update worked)", () ->
			res = localCache.set state.key, state.value2, 0
			true.should.eql res

			# check if the update worked
			res = localCache.get state.key
			state.value2.should.eql res

			# stats should not have changed
			1.should.eql localCache.getStats().keys - state.start.keys
			return

		it "delete the defined key", () ->
			localCache.once "del", (key, val) ->
				state.key.should.eql key
				state.value2.should.eql val
				return
			count = localCache.del state.key
			1.should.eql count

			# check stats
			0.should.eql localCache.getStats().keys - state.start.keys
			return

		it "delete multiple keys (after setting them)", () ->
			keys = ["multiA", "multiB", "multiC"]
			# set the keys
			keys.forEach (key) ->
				res = localCache.set key, state.value3
				true.should.eql res
				return
			# check the keys
			keys.forEach (key) ->
				res = localCache.get key
				state.value3.should.eql res
				return
			# delete 2 of those keys
			count = localCache.del keys[0...2]
			2.should.eql count
			# try to get the deleted keys
			keys[0...2].forEach (key) ->
				res = localCache.get key
				should(res).be.undefined()
				return
			# get the not deleted key
			res = localCache.get keys[2]
			state.value3.should.eql res
			# delete this key, too
			count = localCache.del keys[2]
			1.should.eql count
			# try get the deleted key
			res = localCache.get keys[2]
			should(res).be.undefined()
			# re-deleting the keys should not have to delete an actual key
			count = localCache.del keys
			0.should.eql count
			return

		it "set a key to 0", () ->
			res = localCache.set "zero", 0
			true.should.eql res
			return

		it "get previously set key", () ->
			res = localCache.get "zero"
			0.should.eql res
			return

		it "set a key to an object clone", () ->
			res = localCache.set "clone", state.obj
			true.should.eql res
			return

		it "get cloned object", () ->
			res = localCache.get "clone"
			# should not be === equal
			state.obj.should.not.equal res
			# but should deep equal
			state.obj.should.eql res

			res.b.y = 42
			res2 = localCache.get "clone"
			state.obj.should.eql res2
			return

		it "test promise storage (fulfill before adding to cache)", (done) ->
			deferred_value = "Some deferred value"
			if Promise?
				p = new Promise (fulfill, reject) ->
					fulfill deferred_value
					return
				p.then (value) ->
					deferred_value.should.eql value
					return
				localCache.set "promise", p
				q = localCache.get "promise"
				q.then (value) ->
					done()
					return
			else
				if not process.env.SILENT_MODE?
					console.log "No Promises available in this node version (#{process.version})"
				this.skip()
			return

		it "test promise storage (fulfill after adding to cache)", (done) ->
			deferred_value = "Some deferred value"
			if Promise?
				called  = 0
				callStub = () ->
					called++
					if called is 2
						done()
					return

				p = new Promise (fulfill, reject) ->
					fulfiller = () ->
						fulfill deferred_value
						return
					setTimeout fulfiller, 250
					return
				p.then (value) ->
					deferred_value.should.eql value
					callStub()
					return
				localCache.set "promise", p
				q = localCache.get "promise"
				q.then (value) ->
					deferred_value.should.eql value
					callStub()
					return
			else
				if not process.env.SILENT_MODE?
					console.log "No Promises available in this node version (#{process.version})"
				this.skip()
			return

		it "test es6 map", () ->
			unless Map?
				if not process.env.SILENT_MODE?
					console.log "No Maps available in this node version (#{process.version})"
				this.skip()
				return

			key = randomString 10
			map = new Map([ ["firstkey", "firstvalue"], ["2ndkey", "2ndvalue"], ["thirdkey", "thirdvalue"] ])

			localCache.set key, map

			map.set "fourthkey", "fourthvalue"

			cached_map = localCache.get key
			should( cached_map.get("2ndkey") ).eql "2ndvalue"
			should( cached_map.get "fourthkey" ).be.undefined()
			return

		it "test `useClones = true` with an Object", () ->
			key = randomString 10
			value =
				a: 123
				b: 456
			c = 789

			localCache.set key, value
			value.a = c

			value.should.not.be.eql localCache.get(key)
			return

		it "test `useClones = false` with an Object", () ->
			key = randomString 10
			value =
				a: 123
				b: 456
			c = 789

			localCacheNoClone.set key, value
			value.a = c

			should( value is localCacheNoClone.get(key) ).be.true()
			return

		return

	describe "max key amount", () ->
		before () ->
			state =
				key1: randomString(10)
				key2: randomString(10)
				key3: randomString(10)
				value1: randomString(10)
				value2: randomString(10)
				value3: randomString(10)
			return

		it "exceed max key size", () ->
			setKey = localCacheMaxKeys.set(state.key1, state.value1, 0)
			true.should.eql setKey

			setKey2 = localCacheMaxKeys.set(state.key2, state.value2, 0)
			true.should.eql setKey2

			(() -> localCacheMaxKeys.set(state.key3, state.value3, 0)).should.throw({
				name: "ECACHEFULL"
				message: "Cache max key size exceeded"
			})
			return

		it "remove a key and set another one", () ->
			del = localCacheMaxKeys.del(state.key1)
			1.should.eql del

			setKey3 = localCacheMaxKeys.set(state.key3, state.value3, 0)
			true.should.eql setKey3
			return

		return

	describe "correct and incorrect key types", () ->
		describe "number", () ->
			before () ->
				state =
					keys: []
					val: randomString 20

				for [1..10]
					state.keys.push randomNumber 100000
				return

			it "set", () ->
				for key in state.keys
					res = localCache.set key, state.val
					true.should.eql res
				return

			it "get", () ->
				res = localCache.get state.keys[0]
				state.val.should.eql res
				return

			it "mget", () ->
				res = localCache.mget state.keys[0..1]
				# generate prediction
				prediction = {}
				prediction[state.keys[0]] = state.val
				prediction[state.keys[1]] = state.val
				prediction.should.eql res
				return

			it "del single", () ->
				count = localCache.del state.keys[0]
				1.should.eql count
				return

			it "del multi", () ->
				count = localCache.del state.keys[1..2]
				2.should.eql count
				return

			it "ttl", (done) ->
				success = localCache.ttl state.keys[3], 0.3
				true.should.eql success

				res = localCache.get state.keys[3]
				state.val.should.eql res

				setTimeout(() ->
					res = localCache.get state.keys[3]
					should.not.exist res
					done()
					return
				, 400)
				return

			it "getTtl", () ->
				now = Date.now()
				success = localCache.ttl state.keys[4], 0.5
				true.should.eql success

				ttl = localCache.getTtl state.keys[4]
				(485 < (ttl - now) < 510).should.eql true
				return

			after () ->
				localCache.flushAll false
				return
			return

		describe "string", () ->
			before () ->
				state =
					keys: []
					val: randomString 20

				for [1..10]
					state.keys.push randomString 10
				return

			it "set", () ->
				for key in state.keys
					res = localCache.set key, state.val
					true.should.eql res
				return

			it "get", () ->
				res = localCache.get state.keys[0]
				state.val.should.eql res
				return

			it "mget", () ->
				res = localCache.mget state.keys[0..1]
				# generate prediction
				prediction = {}
				prediction[state.keys[0]] = state.val
				prediction[state.keys[1]] = state.val
				prediction.should.eql res
				return

			it "del single", () ->
				count = localCache.del state.keys[0]
				1.should.eql count
				return

			it "del multi", () ->
				count = localCache.del state.keys[1..2]
				2.should.eql count
				return

			it "ttl", (done) ->
				success = localCache.ttl state.keys[3], 0.3
				true.should.eql success

				res = localCache.get state.keys[3]
				state.val.should.eql res

				setTimeout(() ->
					res = localCache.get state.keys[3]
					should.not.exist res
					done()
					return
				, 400)
				return

			it "getTtl", () ->
				now = Date.now()
				success = localCache.ttl state.keys[4], 0.5
				true.should.eql success

				ttl = localCache.getTtl state.keys[4]
				(485 < (ttl - now) < 510).should.eql true
				return
			return

		describe "boolean - invalid type", () ->
			before () ->
				state =
					keys: [true, false]
					val: randomString 20
				return

			it "set sync-style", () ->
				(() -> localCache.set(state.keys[0], state.val)).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `boolean`"
				})
				return

			it "get sync-style", () ->
				(() -> localCache.get(state.keys[0])).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `boolean`"
				})
				return

			it "mget sync-style", () ->
				(() -> localCache.mget(state.keys)).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `boolean`"
				})
				return

			it "del single sync-style", () ->
				(() -> localCache.del(state.keys[0])).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `boolean`"
				})
				return

			it "del multi sync-style", () ->
				(() -> localCache.del(state.keys)).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `boolean`"
				})
				return

			it "ttl sync-style", () ->
				(() -> localCache.ttl(state.keys[0], 10)).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `boolean`"
				})
				return

			it "getTtl sync-style", () ->
				(() -> localCache.getTtl(state.keys[0])).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `boolean`"
				})
				return

		describe "object - invalid type", () ->
			before () ->
				state =
					keys: [{ a: 1 }, { b: 2 }]
					val: randomString 20
				return

			it "set sync-style", () ->
				(() -> localCache.set(state.keys[0], state.val)).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `object`"
				})
				return

			it "get sync-style", () ->
				(() -> localCache.get(state.keys[0])).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `object`"
				})
				return

			it "mget sync-style", () ->
				(() -> localCache.mget(state.keys)).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `object`"
				})
				return

			it "del single sync-style", () ->
				(() -> localCache.del(state.keys[0])).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `object`"
				})
				return

			it "del multi sync-style", () ->
				(() -> localCache.del(state.keys)).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `object`"
				})
				return

			it "ttl sync-style", () ->
				(() -> localCache.ttl(state.keys[0], 10)).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `object`"
				})
				return

			it "getTtl sync-style", () ->
				(() -> localCache.getTtl(state.keys[0])).should.throw({
					name: "EKEYTYPE"
					message: "The key argument has to be of type `string` or `number`. Found: `object`"
				})
				return
		return

	describe "flush", () ->
		before () ->
			state =
				n: 0
				count: 100
				startKeys: localCache.getStats().keys
				keys: []
				val: randomString 20
			return

		it "set keys", () ->
			for [1..state.count]
				key = randomString 7
				state.keys.push key

			state.keys.forEach (key) ->
				localCache.set key
				state.n++
				return

			state.count.should.eql state.n
			(state.startKeys + state.count).should.eql localCache.getStats().keys
			return

		it "flush keys", () ->
			localCache.flushAll false

			0.should.eql localCache.getStats().keys
			{}.should.eql localCache.data
			return
		return


	describe "many", () ->
		before () ->
			state =
				n: 0
				count: 100000
				keys: []
				val: randomString 20

			for [1..state.count]
				key = randomString 7
				state.keys.push key
			return

		describe "BENCHMARK", () ->
			this.timeout(0)
			# hack so mocha always shows timing information
			this.slow(1)

			it "SET", () ->
				start = Date.now()
				# not using forEach because it's magnitude 10 times slower than for
				# and we are into a benchmark
				for key in state.keys
					should(localCache.set key, state.val, 0).be.ok()
				duration = Date.now() - start
				if not process.env.SILENT_MODE?
					console.log "\tSET: #{state.count} keys to: `#{state.val}` #{duration}ms (#{duration/state.count}ms per item)"
				else
					BENCH[ "SET" ] = 1/(( duration/1000 )/state.count)
				return

			it "GET", () ->
				# this benchmark is a bit useless because the equality check eats up
				# around 3/4 of benchmark time
				start = Date.now()
				for key in state.keys
					state.n++
					state.val.should.eql localCache.get(key)
				duration = Date.now() - start
				if not process.env.SILENT_MODE?
					console.log "\tGET: #{state.count} keys #{duration}ms (#{duration/state.count}ms per item)"
				else
					BENCH[ "GET" ] = 1/(( duration/1000 )/state.count)
				return

			it "check stats", () ->
				stats = localCache.getStats()
				keys = localCache.keys()

				stats.keys.should.eql keys.length
				state.count.should.eql keys.length
				state.n.should.eql keys.length
				return

			after () ->
				if not process.env.SILENT_MODE?
					console.log "\tBenchmark stats:"
					console.log stringify(localCache.getStats(), null, "\t")
				return
			return
		return


	describe "delete", () ->
		this.timeout(0)

		before () ->
			# don't override state because we still need `state.keys`
			state.n = 0
			state.startKeys = localCache.getStats().keys
			return

		it "delete all previously set keys", () ->
			for i in [0...state.count]
				1.should.eql localCache.del state.keys[i]
				state.n++

			state.n.should.eql state.count
			return

		it "delete keys again; should not delete anything", () ->
			for i in [0...state.count]
				0.should.eql localCache.del state.keys[i]
				state.n++

			state.n.should.eql state.count*2
			localCache.getStats().keys.should.eql 0
		return


	describe "stats", () ->
		before () ->
			state =
				n: 0
				start: clone localCache.getStats()
				count: 5
				keylength: 7
				valuelength: 50
				keys: []
				values: []

			for [1..state.count*2]
				key = randomString state.keylength
				value = randomString state.valuelength
				state.keys.push key
				state.values.push value

				true.should.eql localCache.set key, value, 0
				state.n++
			return

		it "get and remove `count` elements", () ->
			for i in [1..state.count]
				state.values[i].should.eql localCache.get state.keys[i]
				state.n++

			for i in [1..state.count]
				1.should.eql localCache.del state.keys[i]
				state.n++

			after = localCache.getStats()
			diff = diffKeys after, state.start

			diff.hits.should.eql 5
			diff.keys.should.eql 5
			diff.ksize.should.eql state.count * state.keylength
			diff.vsize.should.eql state.count * state.valuelength
			return

		it "generate `count` misses", () ->
			for i in [1..state.count]
				# 4 char key should not exist
				should(localCache.get "xxxx").be.undefined()
				state.n++

			after = localCache.getStats()
			diff = diffKeys after, state.start

			diff.misses.should.eql 5
			return

		it "check successful runs", () ->
			state.n.should.eql 5 * state.count
			return
		return


	describe "multi", () ->
		before () ->
			state =
				n: 0
				count: 100
				startKeys: localCache.getStats().keys
				value: randomString 20
				keys: []

			for [1..state.count]
				key = randomString 7
				state.keys.push key

			for key in state.keys
				localCache.set key, state.value, 0
				state.n++

			return

		it "generate a sub-list of keys", () ->
			state.getKeys = state.keys.splice 50, 5
			return

		it "generate prediction", () ->
			state.prediction = {}
			for key in state.getKeys
				state.prediction[key] = state.value
			return

		it "try to mget with a single key", () ->
			(() -> localCache.mget(state.getKeys[0])).should.throw({
				name: "EKEYSTYPE",
				message: "The keys argument has to be an array."
			})
			state.n++
			return

		it "mget the sub-list", () ->
			state.prediction.should.eql localCache.mget state.getKeys
			state.n++
			return

		it "delete keys in the sub-list", () ->
			state.getKeys.length.should.eql localCache.del state.getKeys
			state.n++
			return

		it "try to mget the sub-list again", () ->
			{}.should.eql localCache.mget state.getKeys
			state.n++
			return

		it "check successful runs", () ->
			state.n.should.eql state.count + 4
			return
		return


	describe "ttl", () ->
		before () ->
			state =
				n: 0
				val: randomString 20
				key1: "k1_#{randomString 20}"
				key2: "k2_#{randomString 20}"
				key3: "k3_#{randomString 20}"
				key4: "k4_#{randomString 20}"
				key5: "k5_#{randomString 20}"
				key6: "k6_#{randomString 20}"
				now: Date.now()
			state.keys = [state.key1, state.key2, state.key3, state.key4, state.key5]
			return
		
		describe "has validates expired ttl", () ->
			it "set a key with ttl", () ->
				true.should.eql localCacheTTL.set state.key6, state.val, 0.7
				return
	
			it "check this key immediately", () ->
				true.should.eql localCacheTTL.has state.key6
				return
	
			it "before it times out", () ->
				setTimeout(() ->
					state.n++
					res = localCacheTTL.has state.key6
					res.should.eql true
					state.val.should.eql localCacheTTL.get state.key6
					return
				, 20)
				return
	
			it "and after it timed out", () ->
				setTimeout(() ->
					res = localCacheTTL.has state.key6
					res.should.eql false
					
					state.n++
					should(localCacheTTL.get state.key6).be.undefined()
					return
				, 800)
				return

		it "set a key with ttl", () ->
			res = localCache.set state.key1, state.val, 0.7
			true.should.eql res
			ts = localCache.getTtl state.key1
			if state.now < ts < state.now + 300
				throw new Error "Invalid timestamp"
			return

		it "check this key immediately", () ->
			state.val.should.eql localCache.get state.key1
			return

		it "before it times out", () ->
			setTimeout(() ->
				state.n++
				res = localCache.has state.key1
				res.should.eql true
				state.val.should.eql localCache.get state.key1
				return
			, 20)
			return

		it "and after it timed out", () ->
			setTimeout(() ->
				res = localCache.has state.key1
				res.should.eql false
				
				ts = localCache.getTtl state.key1
				should.not.exist ts

				state.n++
				should(localCache.get state.key1).be.undefined()
				return
			, 700)
			return

		it "set another key with ttl", () ->
			res = localCache.set state.key2, state.val, 0.5
			true.should.eql res
			return

		it "check this key immediately", () ->
			res = localCache.get state.key2
			state.val.should.eql res
			return

		it "before it times out", () ->
			setTimeout(() ->
				state.n++

				state.val.should.eql localCache.get state.key2
				return
			, 20)
			return

		it "and after it timed out, too", () ->
			setTimeout(() ->
				ts = localCache.getTtl state.key2
				should.not.exist ts

				state.n++
				should(localCache.get state.key2).be.undefined()
				return
			, 500)
			return

		describe "test the automatic check", (done) ->
			innerState = null

			before (done) ->
				setTimeout(() ->
					innerState =
						startKeys: localCache.getStats().keys
						key: "autotest"
						val: randomString 20

					done()
					return
				, 1000)
				return

			it "set a key with ttl", () ->
				localCache.once "set", (key) ->
					innerState.key.should.eql key
					return

				true.should.eql localCache.set innerState.key, innerState.val, 0.5

				(innerState.startKeys + 1).should.eql localCache.getStats().keys
				# event handler should have been fired
				0.should.eql localCache.listeners("set").length
				return

			it "and check it's existence", () ->
				innerState.val.should.eql localCache.get innerState.key
				return

			it "wait for 'expired' event", (done) ->
				localCache.once "expired", (key, val) ->
					innerState.key.should.eql key
					(key not in state.keys).should.eql true
					should(localCache.data[key]).be.undefined()
					done()
					return

				setTimeout(() ->
					# trigger ttl check, which will trigger the `expired` event
					localCache._checkData false
					return
				, 550)
				return
			return

		describe "more ttl tests", () ->

			it "set a third key with ttl", () ->
				true.should.eql localCache.set state.key3, state.val, 100
				return

			it "check it immediately", () ->
				state.val.should.eql localCache.get state.key3
				return

			it "set ttl to the invalid key", () ->
				false.should.eql localCache.ttl "#{state.key3}false", 0.3
				return

			it "set ttl to the correct key", () ->
				true.should.eql localCache.ttl state.key3, 0.3
				return

			it "check if the key still exists", () ->
				res = localCache.get state.key3
				state.val.should.eql res
				return

			it "wait until ttl has ended and check if the key was deleted", (done) ->
				setTimeout(() ->
					res = localCache.get state.key3
					should(res).be.undefined()
					should(localCache.data[state.key3]).be.undefined()
					done()
					return
				, 500)
				return

			it "set a key with ttl = 100s (default: infinite), reset it's ttl to default and check if it still exists", () ->
				true.should.eql localCache.set state.key4, state.val, 100

				# check immediately
				state.val.should.eql localCache.get state.key4

				# set ttl to false key
				false.should.eql localCache.ttl "#{state.key4}false"

				# set default ttl (0) to the right key
				true.should.eql localCache.ttl state.key4

				# and check if it still exists
				res = localCache.get state.key4
				state.val.should.eql res
				return

			it "set a key with ttl = 100s (default: 0.3s), reset it's ttl to default, check if it still exists, and wait for its timeout", (done) ->
				true.should.eql localCacheTTL.set state.key5, state.val, 100

				# check immediately
				state.val.should.eql localCacheTTL.get state.key5

				# set ttl to false key
				false.should.eql localCacheTTL.ttl "#{state.key5}false"

				# set default ttl (0.3) to right key
				true.should.eql localCacheTTL.ttl state.key5

				# and check if it still exists
				state.val.should.eql localCacheTTL.get state.key5

				setTimeout(() ->
					res = localCacheTTL.get state.key5
					should.not.exist res

					localCacheTTL._checkData false

					# deep dirty check if key was deleted
					should(localCacheTTL.data[state.key5]).be.undefined()
					done()
					return
				, 350)
				return


			it "set a key key with a cache initialized with no automatic delete on expire should be undefined", (done) ->
				localCacheNoDelete.set state.key1, state.val
				setTimeout(() ->
					res = localCacheNoDelete.get state.key1
					should(res).eql(undefined)
					done()
					return
				, 500)
				return

			it "test issue #78 with expire event not fired", ( done )->
				@timeout( 6000 )
				localCacheTTL2 = new nodeCache({
					stdTTL: 1,
					checkperiod: 0.5
				})
				expCount = 0
				expkeys = [ "ext78_test:a", "ext78_test:b" ]

				localCacheTTL2.set( expkeys[ 0 ], expkeys[ 0 ], 2)
				localCacheTTL2.set( expkeys[ 1 ], expkeys[ 1 ], 3)

				localCacheTTL2.on "expired", ( key, value )->
					key.should.eql( expkeys[ expCount ] )
					value.should.eql( expkeys[ expCount ] )
					expCount++
					return

				setTimeout( ->
					expCount.should.eql( 2 )
					localCacheTTL2.close()
					done()
				, 5000 )
			return

		return

	describe "clone", () ->
		it "a function", (done) ->
			key = randomString 10

			value = () ->
				done()
				return

			localCache.set key, value

			fn = localCache.get key
			fn()
			return

		it "a regex", () ->
			key = randomString 10
			regex = new RegExp "\\b\\w{4}\\b", "g"
			match = "king"
			noMatch = "bla"

			true.should.eql regex.test(match)
			false.should.eql regex.test(noMatch)

			localCache.set key, regex
			cachedRegex = localCache.get key

			true.should.eql cachedRegex.test(match)
			false.should.eql cachedRegex.test(noMatch)
			return
		return

	return
