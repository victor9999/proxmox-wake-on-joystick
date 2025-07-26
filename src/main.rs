use gilrs::{Button, Event, EventType, Gilrs};
use std::env;
use std::process::Command;

#[tokio::main]
async fn main() {
    println!("Starting Proxmox Wake-on-Joystick service...");
    monitor_vm_and_joystick().await;
}

async fn monitor_vm_and_joystick() {
    let vm_id = env::var("PROXMOX_VM_ID").unwrap_or_else(|_| "100".to_string());

    println!("Monitoring VM {vm_id} status continuously...");

    loop {
        let vm_running = is_vm_running(&vm_id).await.unwrap_or(false);

        if vm_running {
            println!("VM {vm_id} is running. Monitoring for VM shutdown...");
            // Wait for VM to stop
            while is_vm_running(&vm_id).await.unwrap_or(false) {
                tokio::time::sleep(tokio::time::Duration::from_secs(10)).await;
            }
            println!("VM {vm_id} has stopped. Starting joystick listener...");
        } else {
            println!("VM {vm_id} is stopped. Starting joystick listener...");
            listen_for_joystick_events(&vm_id).await;
            println!("Joystick listener stopped. Resuming VM monitoring...");
        }
    }
}

async fn listen_for_joystick_events(vm_id: &str) {
    let mut gilrs = Gilrs::new().unwrap_or_else(|e| {
        eprintln!("Failed to initialize gamepad support: {e}");
        std::process::exit(1);
    });

    println!("Listening for RT button press on VM {vm_id}. Press Ctrl+C to exit.");

    let mut vm_check_counter = 0;

    loop {
        // Check VM status every 100 iterations (~1 second if no events)
        vm_check_counter += 1;
        if vm_check_counter >= 100 {
            vm_check_counter = 0;
            if let Ok(true) = is_vm_running(vm_id).await {
                println!(
                    "VM {vm_id} is now running. Stopping joystick listener to allow USB passthrough."
                );
                break;
            }
        }

        // Process joystick events with minimal delay
        while let Some(Event { id, event, time: _ }) = gilrs.next_event() {
            match event {
                EventType::ButtonPressed(Button::RightTrigger2, _) => {
                    println!("RT button pressed! Attempting to wake Proxmox VM...");
                    if let Err(e) = wake_proxmox_vm().await {
                        eprintln!("Failed to wake VM: {e}");
                    } else {
                        println!("VM started successfully. Stopping joystick listener for USB passthrough.");
                        return;
                    }
                }
                EventType::Connected => {
                    let gamepad = gilrs.gamepad(id);
                    println!("Gamepad connected: {} (ID: {id:?})", gamepad.name());
                }
                EventType::Disconnected => {
                    println!("Gamepad disconnected (ID: {id:?})");
                }
                _ => {}
            }
        }

        // Very short sleep to prevent excessive CPU usage
        tokio::time::sleep(tokio::time::Duration::from_millis(10)).await;
    }
}

async fn wake_proxmox_vm() -> Result<(), Box<dyn std::error::Error>> {
    let vm_id = env::var("PROXMOX_VM_ID").unwrap_or_else(|_| "100".to_string());

    // Use qm command directly on the Proxmox host
    let output = Command::new("qm").arg("start").arg(&vm_id).output()?;

    if output.status.success() {
        println!("Successfully started VM {vm_id}");
        if !output.stdout.is_empty() {
            println!("Output: {}", String::from_utf8_lossy(&output.stdout));
        }
    } else {
        eprintln!(
            "Failed to start VM {vm_id}. Exit code: {:?}",
            output.status.code()
        );
        if !output.stderr.is_empty() {
            eprintln!("Error: {}", String::from_utf8_lossy(&output.stderr));
        }
    }

    Ok(())
}

async fn is_vm_running(vm_id: &str) -> Result<bool, Box<dyn std::error::Error>> {
    let output = Command::new("qm").arg("status").arg(vm_id).output()?;

    if output.status.success() {
        let status_output = String::from_utf8_lossy(&output.stdout);
        // Check if status contains "running"
        Ok(status_output.contains("running"))
    } else {
        // If qm status fails, assume VM doesn't exist or is not running
        Ok(false)
    }
}
