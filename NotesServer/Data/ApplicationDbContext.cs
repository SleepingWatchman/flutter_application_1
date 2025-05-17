using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using NotesServer.Models;
using System.Text.Json;

namespace NotesServer.Data
{
    public class ApplicationDbContext : DbContext
    {
        public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
            : base(options)
        {
        }

        public DbSet<Note> Notes { get; set; } = null!;
        public DbSet<Folder> Folders { get; set; } = null!;
        public DbSet<ScheduleEntry> ScheduleEntries { get; set; } = null!;
        public DbSet<PinboardNote> PinboardNotes { get; set; } = null!;
        public DbSet<Connection> Connections { get; set; } = null!;
        public DbSet<NoteImage> NoteImages { get; set; } = null!;
        public DbSet<CollaborationDatabase> CollaborationDatabases { get; set; } = null!;
        public DbSet<SharedDatabase> SharedDatabases { get; set; } = null!;
        public DbSet<CollaborativeDatabase> CollaborativeDatabases { get; set; }
        public DbSet<DatabaseCollaborator> DatabaseCollaborators { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            modelBuilder.Entity<CollaborationDatabase>()
                .HasKey(c => c.Id);

            modelBuilder.Entity<CollaborationDatabase>()
                .Property(c => c.Id)
                .ValueGeneratedOnAdd();

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
                    v => JsonSerializer.Serialize(v, new JsonSerializerOptions()),
                    v => JsonSerializer.Deserialize<List<string>>(v, new JsonSerializerOptions()) ?? new List<string>()
                )
                .Metadata.SetValueComparer(
                    new ValueComparer<List<string>>(
                        (c1, c2) => (c1 == null && c2 == null) || (c1 != null && c2 != null && c1.SequenceEqual(c2)),
                        c => c == null ? 0 : c.Aggregate(0, (a, v) => HashCode.Combine(a, v.GetHashCode())),
                        c => c == null ? new List<string>() : c.ToList()
                    )
                );

            modelBuilder.Entity<Note>(entity =>
            {
                entity.Property(e => e.MetadataJson)
                    .HasConversion(
                        v => v == null ? "{}" : JsonSerializer.Serialize(v, new JsonSerializerOptions()),
                        v => string.IsNullOrEmpty(v) ? "{}" : v
                    );

                entity.Property(e => e.ImagesJson)
                    .HasConversion(
                        v => v == null ? "[]" : JsonSerializer.Serialize(v, new JsonSerializerOptions()),
                        v => string.IsNullOrEmpty(v) ? "[]" : v
                    );

                entity.Ignore(e => e.Metadata);
            });

            modelBuilder.Entity<CollaborativeDatabase>()
                .HasMany(d => d.Collaborators)
                .WithOne(c => c.Database)
                .HasForeignKey(c => c.DatabaseId)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<DatabaseCollaborator>()
                .HasOne(c => c.Database)
                .WithMany(d => d.Collaborators)
                .HasForeignKey(c => c.DatabaseId)
                .OnDelete(DeleteBehavior.Cascade);
        }
    }
} 