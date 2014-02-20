# encoding: utf-8

require 'pg'
require 'tsort'

require 'gadget/version'

module Gadget

  class TsortableHash < Hash
    include ::TSort
    alias tsort_each_node each_key
    def tsort_each_child(node, &block)
      (fetch(node) || []).each(&block)
    end
  end

  def self.tables(conn)
    rs = conn.exec("SELECT c.oid, t.tablename FROM pg_tables t INNER JOIN pg_class c ON c.relname=t.tablename WHERE t.schemaname='public' ORDER BY t.tablename")
    tuples = rs.reduce({}) do | h, row |
      h[row['tablename']] = {
        :oid => row['oid'].to_i,
      }
      h
    end
    rs.clear
    tuples
  end

  def self.columns(conn, tablename = nil)
    sql = <<-END_OF_SQL
SELECT t.tablename, a.attname
FROM pg_catalog.pg_attribute a
INNER JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
INNER JOIN pg_catalog.pg_tables t ON c.relname = t.tablename
WHERE a.attnum >= 0
    END_OF_SQL
    if tablename.nil?
      rs = conn.exec(sql)
    else
      sql += " AND t.tablename = $1"
      rs = conn.exec_params(sql, [ tablename ])
    end
    tuples = rs.reduce({}) do | h, row |
      h[row['tablename']] ||= { :columns => [] }
      h[row['tablename']][:columns] << row['attname']
      h
    end
    rs.clear
    tuples
  end

  def self.foreign_keys(conn, tablename = nil)
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
      name = row['tablename']
      h[name] ||= { :refs => [] }
      col_names = self.columns(conn, name)[name][:columns]
      refcol_names = self.columns(conn, row['refname'])[row['refname']][:columns]
      new_ref = {
        :name => row['name'],
        :cols => row['cols'].sub(/\A\{|\}\z/, '').split(',').map { | idx | col_names[idx.to_i - 1] },
        :refname => row['refname'],
        :refcols => row['refcols'].sub(/\A\{|\}\z/, '').split(',').map { | idx | refcol_names[idx.to_i - 1] },
      }
      h[name][:refs] << new_ref
      h
    end
    rs.clear
    tuples
  end

  def self.constraints(conn, tablename = nil)
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
      name = row['tablename']
      h[name] ||= { :constraints => [] }
      new_constraint = {
        :name => row['name'],
        :kind => case row['constrainttype']
                 when 'c'
                   'check'
                 when 'f'
                   'foreign key'
                 when 'p'
                   'primary key'
                 when 't'
                   'trigger'
                 when 'u'
                   'unique'
                 when 'x'
                   'exclusion'
                 else
                   "*** unknown: '#{row['constrainttype']}'"
                 end,
      }
      h[name][:constraints] << new_constraint
      h
    end
    rs.clear
    tuples
  end

  def self.dependencies(conn)
    tables = self.tables(conn)
    foreign_keys = self.foreign_keys(conn)
    dependencies = tables.reduce({}) do | h, (tablename, _) |
      h[tablename] = []
      refs = foreign_keys[tablename]
      unless refs.nil?
        refs[:refs].each { | ref | h[tablename] << ref[:refname] }
      end
      h
    end
  end

  def self.tables_in_dependency_order(conn)
    self.dependencies(conn).reduce(TsortableHash.new) { | h, (k, v) | h[k] = v; h }.tsort
  end

  def self.dependency_graph(conn)
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

  def self.functions(conn)
    rs = conn.exec(<<-END_OF_SQL)
SELECT p.oid, p.proname, p.proargtypes
FROM pg_catalog.pg_proc p
INNER JOIN pg_catalog.pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
    END_OF_SQL

    tuples = rs.reduce({}) do | h, row |
      h[row['proname']] = {
        :oid => row['oid'].to_i,
        :arg_types => row['proargtypes'].split(/\s+/).map(&:to_i),
      }
      h
    end
    rs.clear
    tuples
  end

  def self.triggers(conn)
    rs = conn.exec(<<-END_OF_SQL)
SELECT tg.oid, tg.tgname, t.tablename, p.proname
FROM pg_catalog.pg_trigger tg
INNER JOIN pg_catalog.pg_class c ON tg.tgrelid = c.oid
INNER JOIN pg_catalog.pg_tables t ON c.relname = t.tablename
INNER JOIN pg_catalog.pg_proc p ON tg.tgfoid = p.oid
WHERE tg.tgconstrrelid = 0
    END_OF_SQL

    tuples = rs.reduce({}) do | h, row |
      h[row['tgname']] = {
        :oid => row['oid'].to_i,
        :tablename => row['tablename'],
        :functionname => row['proname'],
      }
      h
    end
    rs.clear
    tuples
  end

  def self.types(conn)
    rs = conn.exec(<<-END_OF_SQL)
SELECT t.oid, t.typname
FROM pg_catalog.pg_type t
    END_OF_SQL

    tuples = rs.reduce({}) do | h, row |
      h[row['typname']] = {
        :oid => row['oid'].to_i,
      }
      h
    end
    rs.clear
    tuples
  end

end
