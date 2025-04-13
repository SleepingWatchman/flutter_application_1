using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using NotesServer.Models;

namespace NotesServer.Data
{
    public class ApplicationDbContext : DbContext
    {
        public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
            : base(options)
        {
        }

        public DbSet<Note> Notes { get; set; }
        public DbSet<Folder> Folders { get; set; }
        public DbSet<ScheduleEntry> ScheduleEntries { get; set; }
        public DbSet<PinboardNote> PinboardNotes { get; set; }
        public DbSet<Connection> Connections { get; set; }
        public DbSet<NoteImage> NoteImages { get; set; }
        public DbSet<CollaborationDatabase> CollaborationDatabases { get; set; }
        public DbSet<SharedDatabase> SharedDatabases { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            modelBuilder.Entity<CollaborationDatabase>()
                .HasKey(c => c.Id);

            modelBuilder.Entity<CollaborationDatabase>()
                .Property(c => c.UserId)
                .IsRequired();

            modelBuilder.Entity<CollaborationDatabase>()
                .Property(c => c.CreatedAt)
                .IsRequired();

            modelBuilder.Entity<CollaborationDatabase>()
                .Property(c => c.DatabaseName)
                .IsRequired();

            modelBuilder.Entity<CollaborationDatabase>()
                .Property(c => c.ConnectionString)
                .IsRequired();

            modelBuilder.Entity<SharedDatabase>()
                .Property(db => db.Collaborators)
                .HasConversion(
                    v => string.Join(',', v),
                    v => v.Split(',', StringSplitOptions.RemoveEmptyEntries).ToList()
                )
                .Metadata.SetValueComparer(
                    new ValueComparer<List<string>>(
                        (c1, c2) => c1.SequenceEqual(c2),
                        c => c.Aggregate(0, (a, v) => HashCode.Combine(a, v.GetHashCode())),
                        c => c.ToList()
                    )
                );
        }
    }
} 