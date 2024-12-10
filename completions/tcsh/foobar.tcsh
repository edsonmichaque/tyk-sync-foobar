# Command completion
complete foobar.sh 'p/1/(init sync dump import export)/'

# Option completion
complete foobar.sh 'c/--/(help verbose)/' 'c/-/(h v)/'

# Command-specific completions
complete foobar.sh 'n/init/f/' # Complete files for init
complete foobar.sh 'n/sync/d/' # Complete directories for sync
complete foobar.sh 'n/dump/d/' # Complete directories for dump
complete foobar.sh 'n/import/d/' # Complete directories for import
complete foobar.sh 'n/export/d/' # Complete directories for export 