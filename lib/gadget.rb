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
    tuples = rs.reduce({}) { | h, row | h[row['tablename']] = { :oid => row['oid'] }; h }
    rs.clear
    tuples
  end

  def self.columns(conn, tablename = nil)
    sql = <<-END_OF_SQL
SELECT t.tablename, a.attname
FROM pg_attribute a
INNER JOIN pg_class c ON a.attrelid=c.oid
INNER JOIN pg_tables t ON c.relname=t.tablename
    END_OF_SQL
    if tablename.nil?
      rs = conn.exec(sql)
    else
      sql += " WHERE t.tablename=$1"
      rs = conn.exec_params(sql, [ tablename ])
    end
    # tuples = rs.map { | row | row }
    tuples = rs.reduce({}) { | h, row | h[row['tablename']] ||= { :columns => [] }; h[row['tablename']][:columns] << row['attname']; h }
    rs.clear
    tuples
  end

  def self.foreign_keys(conn, tablename = nil)
    sql = <<-END_OF_SQL
SELECT t1.tablename AS tablename, t2.tablename AS refname
FROM pg_constraint
INNER JOIN pg_class c1 ON pg_constraint.conrelid=c1.oid
INNER JOIN pg_tables t1 ON c1.relname=t1.tablename
INNER JOIN pg_class c2 ON pg_constraint.confrelid=c2.oid
INNER JOIN pg_tables t2 ON c2.relname=t2.tablename
WHERE t1.schemaname='public'
AND t2.schemaname='public'
AND pg_constraint.contype='f'
    END_OF_SQL
    if tablename.nil?
      rs = conn.exec(sql)
    else
      sql += " AND t1.tablename=$1"
      rs = conn.exec_params(sql, [ tablename ])
    end
    tuples = rs.reduce({}) { | h, row | h[row['tablename']] ||= { :refs => [] }; h[row['tablename']][:refs] << row['refname']; h }
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
        refs[:refs].each { | ref | h[tablename] << ref }
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

end
