# Gadget

Some methods for getting metadata and other deep details from a PostgreSQL database.

## Installation

Add this line to your application's Gemfile:

    gem 'gadget'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install gadget

## Usage

`#tables(conn)`

Returns a list of all tables in the schema reachable through `conn`.

`#columns(conn, tablename=nil)`

Returns a list of all columns in the schema reachable through `conn`.
If `tablename` is given, returns the columns in only that table.

`#foreign_keys(conn, tablename=nil)`

Returns a list of all foreign keys in the schema reachable through `conn`.
If `tablename` is given, returns the foreign keys in only that table.

`#constraints(conn, tablename=nil)`

Returns a list of all constraints in the schema reachable through `conn`.
If `tablename` is given, returns the constraints in only that table.

`#dependencies(conn)`

Returns a structure representing the dependencies between tables in the schema reachable through `conn`.
Table A is defined as dependent on table B if A contains a foreign key reference to B.

`#tables_in_dependency_order(conn)`

Returns a list of all tables in the schema reachable through `conn`, ordered such that any given table
appears later in the list than all of its dependencies.

`#dependency_graph(conn)`

Returns `.dot` script (suitable for feeding into Graphviz) describing the table dependency graph.

`#functions(conn)`

Returns a list of all functions in the schema reachable through `conn`.

`#sequences(conn)`

Returns a list of all sequences in the schema reachable through `conn`.

`#triggers(conn)`

Returns a list of all triggers in the schema reachable through `conn`.

`#types(conn)`

Returns a list of all types in the schema reachable through `conn`.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
