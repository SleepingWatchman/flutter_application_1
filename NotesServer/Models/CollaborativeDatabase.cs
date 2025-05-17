using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace NotesServer.Models
{
    public class CollaborativeDatabase
    {
        [Key]
        public string Id { get; set; } = Guid.NewGuid().ToString();
        
        [Required]
        public string Name { get; set; }
        
        [Required]
        public string OwnerId { get; set; }
        
        [Required]
        public DateTime CreatedAt { get; set; }
        
        [Required]
        public DateTime LastSync { get; set; }
        
        [Required]
        public int Version { get; set; }
        
        public virtual ICollection<DatabaseCollaborator> Collaborators { get; set; }
    }

    public class DatabaseCollaborator
    {
        [Key]
        public string Id { get; set; } = Guid.NewGuid().ToString();
        
        [Required]
        public string DatabaseId { get; set; }
        
        [Required]
        public string UserId { get; set; }
        
        [Required]
        public string Role { get; set; }
        
        public virtual CollaborativeDatabase Database { get; set; }
    }
} 