test.datastreamIndividual.ExplicitTimestamp
- query on root path
    - returns all the latest values when querying the root path
    - returns string timestamp and reception_timestamp when querying the root path
    - returns numeric timestamp and reception_timestamp when querying the root path with keep_milliseconds
    - returns the specified timestamp when querying the root path
- query on specific path
    - returns the history of values when querying a specific path
    - does not return the reception_timestamp when querying a specific path
    - returns numeric timestamp when querying a specific path with keep_milliseconds
    - returns the specified timestamp when querying a specific path

test.datastreamIndividual.Parametric
- query on root path
    - returns all the latest values when querying the root path
    - returns string timestamp and reception_timestamp when querying the root path
    - returns numeric timestamp and reception_timestamp when querying the root path with keep_milliseconds
- query on specific path
    - does not return the reception_timestamp when querying a specific path
    - returns numeric timestamp when querying a specific path with keep_milliseconds
    - returns the history of values when querying a specific path

test.datastreamIndividual.ServerOwned
- query on root path
    - returns all latest values when querying the root path
    - returns string timestamp and reception_timestamp when querying the root path
    - returns numeric timestamp and reception_timestamp when querying the root path with keep_milliseconds
- query on specific path
    - does not return the reception_timestamp when querying a specific path
    - returns numeric timestamp when querying a specific path with keep_milliseconds
    - returns the history of values when querying a specific path

test.datastreamIndividual.Simple
- query on root path
    - returns all latest values when querying the root path
    - returns string timestamp and reception_timestamp when querying the root path
    - returns numeric timestamp and reception_timestamp when querying the root path with keep_milliseconds
- query on specific path
    - does not return the reception_timestamp when querying a specific path
    - returns numeric timestamp when querying a specific path with keep_milliseconds
    - returns the history of values when querying a specific path



test.datastreamObject.ExplicitTimestamp
- query on root path
    - returns all the latest values when querying the root path
    - returns string timestamp when querying the root path
    - returns numeric timestamp when querying the root path with keep_milliseconds
    - does not return a reception_timestamp when querying the root path
    - returns the specified timestamp when querying the root path
- query on specific object
    - does not return the reception_timestamp when querying a specific object
    - returns the specified timestamp when querying a specific object
    - returns numeric timestamp when querying a specific path with keep_milliseconds
    - returns the history of values when querying a specific object

test.datastreamObject.Parametric
- query on root path
    - returns all the latest values when querying the root path
    - returns string timestamp when querying the root path
    - returns numeric timestamp when querying the root path with keep_milliseconds
- query on specific object
    - does not return the reception_timestamp when querying a specific object
    - returns numeric timestamp when querying a specific path with keep_milliseconds
    - returns the history of values when querying a specific object

test.datastreamObject.ServerOwned
- query on root path
    - returns all the latest values when querying the root path
    - returns string timestamp when querying the root path
    - returns numeric timestamp when querying the root path with keep_milliseconds
- query on specific object
    - does not return the reception_timestamp when querying a specific object
    - returns numeric timestamp when querying a specific path with keep_milliseconds
    - returns the history of values when querying a specific object

test.datastreamObject.Simple
- query on root path
    - returns all the latest values when querying the root path
    - returns string timestamp when querying the root path
    - returns numeric timestamp when querying the root path with keep_milliseconds
- query on specific object
    - does not return the reception_timestamp when querying a specific object
    - returns numeric timestamp when querying a specific path with keep_milliseconds
    - returns the history of values when querying a specific object

TODO:
test.propertiesIndividual.AllowUnset
- query on root path
    - returns all the properties when querying the root path
    - does not return a property where nil was published when querying the root path
    - does not return a property that was deleted when querying the root path
- query on specific path
    - returns the single value when querying a specific path
    - if nil was published, returns empty map when querying a specific path
    - returns empty map instead of a value if the property was deleted when querying a specific path

test.propertiesIndividual.Parametric
- query on root path
    - returns all the properties when querying the root path
- query on specific path
    - returns the single value when querying a specific path

test.propertiesIndividual.ServerOwned
- query on root path
    - returns all the properties when querying the root path
- query on specific path
    - returns the single value when querying a specific path

test.propertiesIndividual.Simple
- query on root path
    - returns all the properties when querying the root path
- query on specific path
    - returns the single value when querying a specific path

## Notes
- Individual datastream: returns the values as `{value: value, timestamp: timestamp}`
- Object datastream: returns the values as `{prop1: value1, prop2: value2, timestamp: timestamp}`
- Object datastream: never returns a reception_timestamp
- Individual property: returns empty map when querying a specific property that was deleted
- Individual property: returns empty map when querying a specific property where nil was published
