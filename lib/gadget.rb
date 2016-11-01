# encoding: utf-8

require "pg"
require "tsort"

require "gadget/version"

## monkey patch Hash to gain .extractable_options?
class Hash
  def extractable_options?
    instance_of?(Hash)
  end
end

## monkey patch Array to gain .extract_options!
class Array
  def extract_options!
    if last.is_a?(Hash) && last.extractable_options?
      pop
    else
      {}
    end
  end
end

module Gadget

  class TsortableHash < Hash
    include ::TSort
    alias tsort_each_node each_key
    def tsort_each_child(node, &block)
      (fetch(node) || []).each(&block)
    end
  end

  # Return a collection enumerating the tables in a database.
  #
  # ==== Usage
  #   tables = Gadget.tables(conn)
  #
  # ==== Parameters
  # * +conn+ - a +PG::Connection+ to the database
  #
  # ==== Returns
  # * a Hash:
  #   table name::  a Hash:
  #     +:oid+::  the table's OID
  def self.tables(conn, *args)
    _ = args.extract_options!

    sql = <<-END_OF_SQL
SELECT c.oid, t.tablename
FROM pg_catalog.pg_tables t
INNER JOIN pg_catalog.pg_class c ON c.relname=t.tablename
WHERE t.schemaname='public'
    END_OF_SQL
    rs = conn.exec(sql)
    tuples = rs.reduce({}) do | h, row |
      h[row["tablename"]] = {
        oid: row["oid"].to_i,
      }
      h
    end
    rs.clear
    tuples
  end

  # Return a collection enumerating the columns in a table or database.
  #
  # ==== Usage
  #   columns = Gadget.columns(conn)
  #   columns_in_table = Gadget.columns(conn, "tablename")
  #
  # ==== Parameters
  # * +conn+ - a +PG::Connection+ to the database
  # * +tablename - if given, return columns only for the named table
  #
  # ==== Returns
  # * a Hash:
  #   table name::  a Hash:
  #     +:columns+::  an Array of column names
  def self.columns(conn, *args)
    options = args.extract_options!
    tablename = args.shift
    nspname = args.shift || "public"

    sql = <<-END_OF_SQL
SELECT t.tablename, a.attname, ns.nspname
FROM pg_catalog.pg_attribute a
INNER JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
INNER JOIN pg_catalog.pg_tables t ON c.relname = t.tablename
INNER JOIN pg_catalog.pg_namespace ns ON c.relnamespace = ns.oid
WHERE a.attnum >= 0
AND t.schemaname = ns.nspname
AND ns.nspname = $1
    END_OF_SQL
    unless options[:include_dropped]
      sql += " AND a.attisdropped IS FALSE"
    end
    if tablename.nil?
      rs = conn.exec_params(sql, [ nspname ])
    else
      sql += " AND t.tablename = $2"
      rs = conn.exec_params(sql, [ nspname, tablename ])
    end
    tuples = rs.reduce({}) do | h, row |
      h[row["tablename"]] ||= { columns: [] }
      h[row["tablename"]][:columns] << row["attname"]
      h
    end
    rs.clear
    tuples
  end

  # Return a collection enumerating the foreign keys in a table or database.
  #
  # ==== Usage
  #   fks = Gadget.foreign_keys(conn)
  #   fks_in_table = Gadget.foreign_keys(conn, "tablename")
  #
  # ==== Parameters
  # * +conn+ - a +PG::Connection+ to the database
  # * +tablename - if given, return foreign keys only for the named table
  #
  # ==== Returns
  # * a Hash:
  #   table name::  a Hash:
  #     +:refs+::   an Array of Hashes:
  #       +:name+::       the name of the foreign key
  #       +:cols+::       the columns in _this table_ that make up the foreign key
  #       +:ref_name+::   the name of the table referred to by this foreign key
  #       +:ref_cols+::   the columns in _the other table_ that are referred to by this foreign key
  def self.foreign_keys(conn, *args)
    _ = args.extract_options!
    tablename = args.shift

    sql = <<-END_OF_SQL
SELECT pg_constraint.conname AS name,
       t1.tablename AS tablename, pg_constraint.conkey AS cols,
       t2.tablename AS refname, pg_constraint.confkey AS refcols
FROM pg_catalog.pg_constraint
INNER JOIN pg_catalog.pg_class c1 ON pg_constraint.conrelid = c1.oid
INNER JOIN pg_catalog.pg_tables t1 ON c1.relname = t1.tablename
INNER JOIN pg_catalog.pg_class c2 ON pg_constraint.confrelid = c2.oid
INNER JOIN pg_catalog.pg_tables t2 ON c2.relname = t2.tablename
WHERE t1.schemaname = 'public'
AND t2.schemaname = 'public'
AND pg_constraint.contype = 'f'
    END_OF_SQL
    if tablename.nil?
      rs = conn.exec(sql)
    else
      sql += " AND t1.tablename = $1"
      rs = conn.exec_params(sql, [ tablename ])
    end
    tuples = rs.reduce({}) do | h, row |
      name = row["tablename"]
      h[name] ||= { refs: [] }
      col_names = self.columns(conn, name, include_dropped: true)[name][:columns]
      refcol_names = self.columns(conn, row["refname"], include_dropped: true)[row["refname"]][:columns]
      new_ref = {
        name: row["name"],
        cols: row["cols"].sub(/\A\{|\}\z/, "").split(",").map { | idx | col_names[idx.to_i - 1] },
        ref_name: row["refname"],
        ref_cols: row["refcols"].sub(/\A\{|\}\z/, "").split(",").map { | idx | refcol_names[idx.to_i - 1] },
      }
      h[name][:refs] << new_ref
      h
    end
    rs.clear
    tuples
  end

  # Return a collection enumerating the constraints in a table or database.
  #
  # ==== Usage
  #   constraints = Gadget.constraints(conn)
  #   constraints_in_table = Gadget.constraints(conn, "tablename")
  #
  # ==== Parameters
  # * +conn+ - a +PG::Connection+ to the database
  # * +tablename - if given, return constraints only for the named table
  #
  # ==== Returns
  # * a Hash:
  #   table name::  a Hash:
  #     +:constraints+::  an Array of Hashes:
  #       +:name+::   the name of the constraint
  #       +:kind+::   the kind of the constraint:
  #         * +check+
  #         * +exclusion+
  #         * +foreign key+
  #         * +primary key+
  #         * +trigger+
  #         * +unique+
  def self.constraints(conn, *args)
    _ = args.extract_options!
    tablename = args.shift

    sql = <<-END_OF_SQL
SELECT pg_constraint.conname AS name,
       pg_constraint.contype AS constrainttype,
       t.tablename AS tablename
FROM pg_catalog.pg_constraint
INNER JOIN pg_catalog.pg_class c ON pg_constraint.conrelid = c.oid
INNER JOIN pg_catalog.pg_tables t ON c.relname = t.tablename
WHERE t.schemaname = 'public'
    END_OF_SQL
    if tablename.nil?
      rs = conn.exec(sql)
    else
      sql += " AND t.tablename = $1"
      rs = conn.exec_params(sql, [ tablename ])
    end
    tuples = rs.reduce({}) do | h, row |
      name = row["tablename"]
      h[name] ||= { constraints: [] }
      new_constraint = {
        name: row["name"],
        kind: case row["constrainttype"]
              when "c"
                "check"
              when "f"
                "foreign key"
              when "p"
                "primary key"
              when "t"
                "trigger"
              when "u"
                "unique"
              when "x"
                "exclusion"
              else
                %Q(*** unknown: "#{row["constrainttype"]}"")
              end,
      }
      h[name][:constraints] << new_constraint
      h
    end
    rs.clear
    tuples
  end

  # Return a collection enumerating the dependencies between tables in a database.
  # A table +a+ is considered to be dependent on a table +b+ if +a+ has a foreign key constraint
  # that refers to +b+.
  #
  # ==== Usage
  #   dependencies = Gadget.dependencies(conn)
  #
  # ==== Parameters
  # * +conn+ - a +PG::Connection+ to the database
  #
  # ==== Returns
  # * a Hash:
  #   table name::  an Array of table names
  def self.dependencies(conn, *args)
    _ = args.extract_options!

    tables = self.tables(conn)
    foreign_keys = self.foreign_keys(conn)
    tables.reduce({}) do | h, (tablename, _) |
      h[tablename] = []
      refs = foreign_keys[tablename]
      unless refs.nil?
        refs[:refs].each { | ref | h[tablename] << ref[:ref_name] }
      end
      h
    end
  end

  # Return a collection enumerating the tables in a database in dependency order.
  # If a table +a+ is dependent on a table +b+, then +a+ will appear _after_ +b+ in the collection.
  #
  # ==== Usage
  #   dependencies = Gadget.dependencies(conn)
  #
  # ==== Parameters
  # * +conn+ - a +PG::Connection+ to the database
  #
  # ==== Returns
  # * a Hash:
  #   table name::  an Array of table names
  def self.tables_in_dependency_order(conn, *args)
    _ = args.extract_options!
    self.dependencies(conn).reduce(TsortableHash.new) { | h, (k, v) | h[k] = v; h }.tsort
  end

  # Print dot (Graphviz data format) describing the dependency graph for a database to stdout.
  #
  # ==== Usage
  #   Gadget.dependency_graph(conn)
  #
  # ==== Parameters
  # * +conn+ - a +PG::Connection+ to the database
  def self.dependency_graph(conn, *args)
    _ = args.extract_options!

    puts "digraph dependencies {"
    self.dependencies(conn).each do | tablename, deps |
      if deps.empty?
        puts %Q<"#{tablename}">
      else
        deps.each { | dep | puts %Q|"#{tablename}" -> "#{dep}"| }
      end
    end
    puts "}"
  end

  # Return a collection enumerating the functions in a database.
  #
  # ==== Usage
  #   functions = Gadget.functions(conn)
  #
  # ==== Parameters
  # * +conn+ - a +PG::Connection+ to the database
  #
  # ==== Returns
  # * a Hash:
  #   function name::  a Hash:
  #     +:oid+::        the function's OID
  #     +:arg_types+::  the type IDs for the arguments to the function
  def self.functions(conn, *args)
    _ = args.extract_options!

    rs = conn.exec(<<-END_OF_SQL)
SELECT p.oid, p.proname, p.proargtypes
FROM pg_catalog.pg_proc p
INNER JOIN pg_catalog.pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
    END_OF_SQL

    tuples = rs.reduce({}) do | h, row |
      h[row["proname"]] = {
        oid: row["oid"].to_i,
        arg_types: row["proargtypes"].split(/\s+/).map(&:to_i),
      }
      h
    end
    rs.clear
    tuples
  end

  # Return a collection enumerating the sequences in a database.
  #
  # ==== Usage
  #   sequences = Gadget.sequences(conn)
  #
  # ==== Parameters
  # * +conn+ - a +PG::Connection+ to the database
  #
  # ==== Returns
  # * a Hash:
  #   sequence name::  a Hash:
  #     +:oid+::  the sequence's OID
  def self.sequences(conn, *args)
    _ = args.extract_options!

    sql = <<-END_OF_SQL
SELECT c.oid, c.relname
FROM pg_catalog.pg_class c
INNER JOIN pg_catalog.pg_namespace n on c.relnamespace = n.oid
WHERE c.relkind = 'S'
AND n.nspname = 'public'
    END_OF_SQL
    rs = conn.exec(sql)
    tuples = rs.reduce({}) do | h, row |
      h[row["relname"]] = {
        oid: row["oid"].to_i,
      }
      h
    end
    rs.clear
    tuples
  end

  # Return a collection enumerating the triggers in a database.
  #
  # ==== Usage
  #   triggers = Gadget.triggers(conn)
  #
  # ==== Parameters
  # * +conn+ - a +PG::Connection+ to the database
  #
  # ==== Returns
  # * a Hash:
  #   trigger name::  a Hash:
  #     +:oid+::            the trigger's OID
  #     +:table_name+::     the table on which the trigger is defined
  #     +:function_name+::  the name of the trigger's function
  def self.triggers(conn, *args)
    _ = args.extract_options!
    tablename = args.shift

    sql = <<-END_OF_SQL
SELECT tg.oid, tg.tgname, t.tablename, p.proname
FROM pg_catalog.pg_trigger tg
INNER JOIN pg_catalog.pg_class c ON tg.tgrelid = c.oid
INNER JOIN pg_catalog.pg_tables t ON c.relname = t.tablename
INNER JOIN pg_catalog.pg_proc p ON tg.tgfoid = p.oid
WHERE tg.tgconstrrelid = 0
    END_OF_SQL
    if tablename.nil?
      rs = conn.exec(sql)
    else
      sql += " AND t.tablename = $1"
      rs = conn.exec_params(sql, [ tablename ])
    end
    tuples = rs.reduce({}) do | h, row |
      h[row["tgname"]] = {
        oid: row["oid"].to_i,
        table_name: row["tablename"],
        function_name: row["proname"],
      }
      h
    end
    rs.clear
    tuples
  end

  # Return a collection enumerating the types in a database.
  #
  # ==== Usage
  #   types = Gadget.types(conn)
  #
  # ==== Parameters
  # * +conn+ - a +PG::Connection+ to the database
  #
  # ==== Returns
  # * a Hash:
  #   type name::  a Hash:
  #     +:oid+::  the type's OID
  def self.types(conn, *args)
    _ = args.extract_options!

    rs = conn.exec(<<-END_OF_SQL)
SELECT t.oid, t.typname
FROM pg_catalog.pg_type t
    END_OF_SQL

    tuples = rs.reduce({}) do | h, row |
      h[row["typname"]] = {
        oid: row["oid"].to_i,
      }
      h
    end
    rs.clear
    tuples
  end

end
