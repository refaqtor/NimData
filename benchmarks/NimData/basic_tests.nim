
import future
import strutils
import nimdata
import times

import nimdata/schema_parser
import nimdata/utils
import parseutils

let pipe = open("benchmarks/output.log", fmWrite)

template runTimed(name: string, numRepeats: int, body: untyped) =
  #echo "Running: ", name, "..."
  stdout.write "Running: $1" % (name | -40)
  var runTimes = newSeq[float]()
  for repeat in 0 .. <numRepeats:
    let t1 = epochTime()
    body
    let t2 = epochTime()
    runTimes.add(t2 - t1)

  let df = DF.fromSeq(runTimes)
  #echo "Time mean: ", df.mean(), " min: ", df.min(), " max: ", df.max()
  echo "min: $1    mean: $2    max: $3" % [
    df.min()  | (6, 3),
    df.mean() | (6, 3),
    df.max()  | (6, 3)
  ]

template runTimed(name: string, body: untyped) =
  runTimed(name, 3, body)


proc parserGeneratedV01*(s: string): tuple[floatA: float, floatB: float, intA: int, intB: int] =
  # This was the parser generated by the very first macro attempt,
  # but was pretty slow due to the manual split, and wouldn't allow
  # to handle escaped strings anyway.
  let fields = s.split(',')
  if fields.len != 4:
    raise newException(IOError, "Unexpected number of fields")
  result.floatA = parseFloat(fields[0])
  result.floatB = parseFloat(fields[1])
  result.intA = parseInt(fields[2])
  result.intB = parseInt(fields[3])


proc parserGeneratedV02*(s: string): tuple[floatA: float, floatB: float, intA: int64, intB: int64] =
  # Improved parser, still many edge cases to handle...
  var i = 0
  var reachedEnd = false
  i += parseBiggestFloat(s, result.floatA, start=i)
  skipPastSep(s, i, reachedEnd, ',')
  i += parseBiggestFloat(s, result.floatB, start=i)
  skipPastSep(s, i, reachedEnd, ',')
  i += parseBiggestInt(s, result.intA, start=i)
  skipPastSep(s, i, reachedEnd, ',')
  i += parseBiggestInt(s, result.intB, start=i)


proc runTestsCount() =
  const schema = [
    floatCol("floatA"),
    floatCol("floatB"),
    intCol("intA"),
    intCol("intB"),
  ]

  runTimed("Pure iteration"):
    discard DF.fromFile("test_01.csv")
              .count()

  runTimed("With parsing"):
    discard DF.fromFile("test_01.csv")
              .map(schemaParser(schema, ','))
              .count()

  runTimed("With dummy parsing"):
    discard DF.fromFile("test_01.csv")
              .map(x => (floatA: 1.0, floatB: 2.0, intA: 1, intB: 2))
              .count()

  runTimed("With parsing (using manual parser 1)"):
    discard DF.fromFile("test_01.csv")
              .map(parserGeneratedV01)
              .count()

  runTimed("With parsing (using manual parser 2)"):
    discard DF.fromFile("test_01.csv")
              .map(parserGeneratedV02)
              .count()

  runTimed("With parsing + 1 dummy map"):
    discard DF.fromFile("test_01.csv")
              .map(schemaParser(schema, ','))
              .map(x => x)
              .count()

  runTimed("With parsing + 2 dummy map"):
    discard DF.fromFile("test_01.csv")
              .map(schemaParser(schema, ','))
              .map(x => x)
              .map(x => x)
              .count()

  runTimed("With parsing + 1 dummy filter"):
    discard DF.fromFile("test_01.csv")
              .map(schemaParser(schema, ','))
              .filter(x => true)
              .count()

  runTimed("With parsing + 2 dummy filter"):
    discard DF.fromFile("test_01.csv")
              .map(schemaParser(schema, ','))
              .filter(x => true)
              .filter(x => true)
              .count()

  runTimed("With caching"):
    discard DF.fromFile("test_01.csv")
              .map(schemaParser(schema, ','))
              .cache()
              .count()


proc runTestsColumnAverages() =
  const schema = [
    floatCol("floatA"),
    floatCol("floatB"),
    intCol("intA"),
    intCol("intB"),
  ]
  runTimed("Column averages"):
    let df = DF.fromFile("test_01.csv")
               .map(schemaParser(schema, ','))
               .cache()
    pipe.writeLine df.map(x => x.floatA).mean()
    pipe.writeLine df.map(x => x.floatB).mean()
    pipe.writeLine df.map(x => x.intA).mean()
    pipe.writeLine df.map(x => x.intB).mean()


proc runTestsUniqueValues() =
  const schema = [
    floatCol("floatA"),
    floatCol("floatB"),
    intCol("intA"),
    intCol("intB"),
  ]

  runTimed("Unique values 1", 3):
    let count = DF.fromFile("test_01.csv")
                  .map(schemaParser(schema, ','))
                  .map(x => x.intA)
                  .unique()
                  .count()
    pipe.writeLine count

  runTimed("Unique values 2", 3):
    let count = DF.fromFile("test_01.csv")
                  .map(schemaParser(schema, ','))
                  .map(x => (x.intA, x.intB))
                  .unique()
                  .count()
    pipe.writeLine count


proc runTestsJoin() =
  runTimed("Join", 3):
    const schemaA = [
      intCol("K1"),
      intCol("K2"),
      intCol("K3"),
      floatCol("valA"),
    ]
    const schemaB = [
      intCol("K1"),
      intCol("K2"),
      intCol("K3"),
      floatCol("valB"),
    ]
    let dfA = DF.fromFile("test_02_a.csv").map(schemaParser(schemaA, ','))
    let dfB = DF.fromFile("test_02_b.csv").map(schemaParser(schemaB, ','))

    let joined = join(dfA, dfB, on=[K1, K2, K3])
    echo joined.map(x => x.valA - x.valB).mean()


#runTestsCount()
#runTestsColumnAverages()
#runTestsUniqueValues()
runTestsJoin()
